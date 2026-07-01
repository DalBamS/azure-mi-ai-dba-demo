#!/usr/bin/env python3
"""
E - Synthesize a realistic game workload profile from a natural-language request.

Turns an ops ask like:
    "런칭 첫날 동접 5만, 재화 40%/랭킹 30%"
into concrete, runnable knobs for the existing load tooling:
    - workload/game-driver  ->  WORKLOAD_MIX_* + WORKLOAD_CONCURRENCY  (.env snippet)
    - workload/hammerdb     ->  count_ware / num_vu suggestions

Design notes
------------
* Deterministic, dependency-free (Python stdlib only) so it runs anywhere and
  produces the same profile for the same request - good for a repeatable demo.
* The data it drives is SYNTHETIC (seeded game schema). No production data and
  no PII are involved: we synthesize *shape and volume*, not records.
* The AI-harness angle: an LLM/agent extracts the intent (CCU + mix) and this
  script encodes the deterministic mapping to tool parameters. Pair it with
  01_capture_top_queries.sql to reconcile the requested mix with real Query
  Store shares, and 03_eval.sql to score the match.

Heuristics (explicit + demo-tunable)
------------------------------------
* concurrency (driver worker threads) is NOT the raw CCU. Only a small fraction
  of concurrent players is issuing a DB call at any instant:
      threads = clamp(round(CCU * ACTIVE_RATIO), 1, 512)          ACTIVE_RATIO=0.02
* HammerDB baseline OLTP sizing (background load, separate DB):
      count_ware = clamp(round(CCU / 2500), 4, 200)
      num_vu     = clamp(threads // 2, 2, 128)
These are transparent demo assumptions - override with flags and say so on stage.

Usage
-----
    python 02_synthesize_profile.py --request "런칭 첫날 동접 5만, 재화 40%/랭킹 30%"
    python 02_synthesize_profile.py --request "peak 20000 ccu, ranking 50% inventory 20%" --emit-env profile.env
"""
from __future__ import annotations

import argparse
import re
import sys

ACTIVE_RATIO = 0.02          # fraction of CCU hitting the DB at any instant
THREADS_MIN, THREADS_MAX = 1, 512

# category -> keywords (Korean + English) used to read the requested mix
CATEGORY_KEYWORDS = {
    "currency_transfer": ["재화", "화폐", "골드", "currency", "gold"],
    "ranking_query":     ["랭킹", "리더보드", "순위", "ranking", "leaderboard", "rank"],
    "inventory_update":  ["인벤", "인벤토리", "아이템", "inventory", "item"],
}
CATEGORY_ORDER = ["currency_transfer", "ranking_query", "inventory_update"]


def parse_ccu(text: str) -> int:
    """Extract concurrent-user count. Understands 만/천 (KR) and k/m (EN)."""
    t = text.replace(",", "")
    # Korean 만 (10,000) / 천 (1,000), e.g. "5만", "3.5만"
    m = re.search(r"(\d+(?:\.\d+)?)\s*만", t)
    if m:
        return int(float(m.group(1)) * 10_000)
    m = re.search(r"(\d+(?:\.\d+)?)\s*천", t)
    if m:
        return int(float(m.group(1)) * 1_000)
    # English 20k / 1.5m
    m = re.search(r"(\d+(?:\.\d+)?)\s*[kK]\b", t)
    if m:
        return int(float(m.group(1)) * 1_000)
    m = re.search(r"(\d+(?:\.\d+)?)\s*[mM]\b", t)
    if m:
        return int(float(m.group(1)) * 1_000_000)
    # plain number near a CCU/동접 keyword, else the largest bare integer
    m = re.search(r"(?:동접|ccu|users?|동시접속)\D{0,6}(\d{3,})", t, re.IGNORECASE)
    if m:
        return int(m.group(1))
    nums = [int(n) for n in re.findall(r"\d{3,}", t)]
    return max(nums) if nums else 10_000


def parse_mix(text: str) -> dict[str, int]:
    """Extract per-category percentages; distribute the remainder sensibly."""
    shares: dict[str, int] = {}
    for cat, kws in CATEGORY_KEYWORDS.items():
        for kw in kws:
            # "재화 40%", "ranking 30 %", "40% 재화"
            for pat in (rf"{kw}\s*[:=]?\s*(\d{{1,3}})\s*%", rf"(\d{{1,3}})\s*%\s*{kw}"):
                m = re.search(pat, text, re.IGNORECASE)
                if m:
                    shares[cat] = int(m.group(1))
                    break
            if cat in shares:
                break

    total = sum(shares.values())
    if total > 100:
        # normalize down proportionally
        shares = {k: round(v * 100 / total) for k, v in shares.items()}
        total = sum(shares.values())

    if not shares:
        # no mix specified at all -> game-driver default 40/40/20 (see game-driver README)
        shares = {"currency_transfer": 40, "inventory_update": 40, "ranking_query": 20}
    else:
        remainder = 100 - total
        missing = [c for c in CATEGORY_ORDER if c not in shares]
        if remainder > 0 and missing:
            base = remainder // len(missing)
            for i, c in enumerate(missing):
                shares[c] = base + (1 if i < remainder - base * len(missing) else 0)

    for c in CATEGORY_ORDER:
        shares.setdefault(c, 0)

    # fix rounding so the three add up to exactly 100
    drift = 100 - sum(shares[c] for c in CATEGORY_ORDER)
    if drift:
        shares[max(CATEGORY_ORDER, key=lambda c: shares[c])] += drift
    return shares


def clamp(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def synthesize(request: str, active_ratio: float, duration: int) -> dict:
    ccu = parse_ccu(request)
    mix = parse_mix(request)
    threads = clamp(round(ccu * active_ratio), THREADS_MIN, THREADS_MAX)
    return {
        "request": request,
        "ccu": ccu,
        "active_ratio": active_ratio,
        "mix": mix,
        "driver": {
            "WORKLOAD_CONCURRENCY": threads,
            "WORKLOAD_DURATION_SECONDS": duration,
            "WORKLOAD_MIX_CURRENCY_TRANSFER": mix["currency_transfer"],
            "WORKLOAD_MIX_RANKING_QUERY": mix["ranking_query"],
            "WORKLOAD_MIX_INVENTORY_UPDATE": mix["inventory_update"],
        },
        "hammerdb": {
            "count_ware": clamp(round(ccu / 2500), 4, 200),
            "num_vu": clamp(threads // 2, 2, 128),
        },
    }


def render(profile: dict) -> str:
    d = profile["driver"]
    h = profile["hammerdb"]
    lines = [
        "# ---------------------------------------------------------------------------",
        "# Synthesized load profile (SYNTHETIC data / no PII) - generated by demo E.",
        f'#   request : {profile["request"]}',
        f'#   CCU     : {profile["ccu"]:,}  (active_ratio={profile["active_ratio"]})',
        f'#   mix     : currency {profile["mix"]["currency_transfer"]}% / '
        f'ranking {profile["mix"]["ranking_query"]}% / inventory {profile["mix"]["inventory_update"]}%',
        "# game-driver: copy into repo-root .env, then `python workload/game-driver/driver.py`",
        "# ---------------------------------------------------------------------------",
        f'WORKLOAD_CONCURRENCY={d["WORKLOAD_CONCURRENCY"]}',
        f'WORKLOAD_DURATION_SECONDS={d["WORKLOAD_DURATION_SECONDS"]}',
        f'WORKLOAD_MIX_CURRENCY_TRANSFER={d["WORKLOAD_MIX_CURRENCY_TRANSFER"]}',
        f'WORKLOAD_MIX_RANKING_QUERY={d["WORKLOAD_MIX_RANKING_QUERY"]}',
        f'WORKLOAD_MIX_INVENTORY_UPDATE={d["WORKLOAD_MIX_INVENTORY_UPDATE"]}',
        "",
        "# HammerDB TPROC-C baseline (separate DB) - set in build_tproc.tcl / run_tproc.tcl:",
        f'#   diset tpcc mssqls_count_ware {h["count_ware"]}',
        f'#   diset tpcc mssqls_num_vu     {h["num_vu"]}',
    ]
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Synthesize a game workload profile from a natural-language request.")
    ap.add_argument("--request", "-r", required=True, help='e.g. "런칭 첫날 동접 5만, 재화 40%/랭킹 30%"')
    ap.add_argument("--active-ratio", type=float, default=ACTIVE_RATIO, help="fraction of CCU issuing a DB call at any instant")
    ap.add_argument("--duration", type=int, default=0, help="WORKLOAD_DURATION_SECONDS (0 = run until Ctrl+C)")
    ap.add_argument("--emit-env", metavar="PATH", help="also write the .env snippet to this file")
    args = ap.parse_args(argv)

    profile = synthesize(args.request, args.active_ratio, args.duration)
    snippet = render(profile)
    sys.stdout.write(snippet)
    if args.emit_env:
        with open(args.emit_env, "w", encoding="utf-8") as fh:
            fh.write(snippet)
        sys.stderr.write(f"\n[written] {args.emit_env}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
