"""Steady-state game load driver.

Runs a weighted mix of game transactions across N worker threads against the
Azure SQL MI game database, so the demo environment always has realistic
traffic flowing and issues can be reproduced on top of it.

Usage
-----
    pip install -r requirements.txt
    # configure .env first (see repo-root .env.example) — never hardcode secrets
    python driver.py                 # run until Ctrl+C (or WORKLOAD_DURATION_SECONDS)
    python driver.py --duration 120  # run for 120 seconds
    python driver.py --concurrency 16

The transaction mix and connection behavior (incl. OLE DB SET-option mimicry)
are configured via environment variables — see config.py / .env.example.
"""

from __future__ import annotations

import argparse
import random
import signal
import threading
import time

import pyodbc

import transactions as tx
from config import Config
from db import connect

_stop = threading.Event()


class Stats:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.committed = 0
        self.deadlocks = 0
        self.errors = 0

    def add(self, committed: int = 0, deadlocks: int = 0, errors: int = 0) -> None:
        with self.lock:
            self.committed += committed
            self.deadlocks += deadlocks
            self.errors += errors


def _resolve_player_count(cfg: Config) -> int:
    if cfg.seed_players > 0:
        return cfg.seed_players
    conn = connect(cfg)
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM dbo.players;")
        count = int(cur.fetchone()[0])
        return max(count, 1)
    finally:
        conn.close()


def _build_choices(cfg: Config) -> list[str]:
    """Expand the configured mix percentages into a weighted choice list."""
    weighted: list[str] = []
    weighted += ["currency_transfer"] * max(0, cfg.mix_currency_transfer)
    weighted += ["inventory_update"] * max(0, cfg.mix_inventory_update)
    weighted += ["ranking_query"] * max(0, cfg.mix_ranking_query)
    return weighted or ["ranking_query"]


def _is_deadlock(err: pyodbc.Error) -> bool:
    # SQL Server error 1205 = deadlock victim.
    return any("1205" in str(arg) for arg in err.args)


def _worker(worker_id: int, cfg: Config, player_count: int, choices: list[str], stats: Stats) -> None:
    conn = None
    while not _stop.is_set():
        try:
            if conn is None:
                conn = connect(cfg)
            op = random.choice(choices)
            if op == "currency_transfer":
                tx.currency_transfer(conn, player_count)
            elif op == "inventory_update":
                tx.inventory_update(conn, player_count, cfg.seed_items_per_player)
            else:
                tx.ranking_query(conn, cfg.seed_season)
            stats.add(committed=1)
        except pyodbc.Error as exc:
            if _is_deadlock(exc):
                stats.add(deadlocks=1)
            else:
                stats.add(errors=1)
            # Reconnect on connection-level failures.
            if conn is not None:
                try:
                    conn.close()
                except pyodbc.Error:
                    pass
                conn = None
            time.sleep(0.05)
    if conn is not None:
        try:
            conn.close()
        except pyodbc.Error:
            pass


def _reporter(stats: Stats, start: float) -> None:
    last = 0
    while not _stop.is_set():
        time.sleep(5)
        with stats.lock:
            total = stats.committed
            deadlocks = stats.deadlocks
            errors = stats.errors
        elapsed = time.time() - start
        tps = (total - last) / 5.0
        last = total
        print(
            f"[{elapsed:6.0f}s] committed={total:<10} "
            f"tps(5s)={tps:8.1f} deadlocks={deadlocks:<6} errors={errors}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Game load driver for Azure SQL MI demo.")
    parser.add_argument("--concurrency", type=int, default=None)
    parser.add_argument("--duration", type=int, default=None, help="seconds; 0 = until Ctrl+C")
    args = parser.parse_args()

    cfg = Config.from_env()
    if args.concurrency is not None:
        cfg.concurrency = args.concurrency
    if args.duration is not None:
        cfg.duration_seconds = args.duration

    print(f"Connecting to {cfg.server}/{cfg.database} as auth_mode={cfg.auth_mode} "
          f"(mimic OLE DB SET options: {cfg.mimic_oledb_set_options})")
    player_count = _resolve_player_count(cfg)
    choices = _build_choices(cfg)
    print(f"player_count={player_count} concurrency={cfg.concurrency} "
          f"mix={{transfer:{cfg.mix_currency_transfer}, inventory:{cfg.mix_inventory_update}, "
          f"ranking:{cfg.mix_ranking_query}}}")

    def _handle_signal(signum, frame):  # noqa: ANN001
        print("\nStopping...")
        _stop.set()

    signal.signal(signal.SIGINT, _handle_signal)
    try:
        signal.signal(signal.SIGTERM, _handle_signal)
    except (ValueError, AttributeError):
        pass

    stats = Stats()
    start = time.time()

    workers = [
        threading.Thread(target=_worker, args=(i, cfg, player_count, choices, stats), daemon=True)
        for i in range(cfg.concurrency)
    ]
    reporter = threading.Thread(target=_reporter, args=(stats, start), daemon=True)
    for w in workers:
        w.start()
    reporter.start()

    try:
        if cfg.duration_seconds > 0:
            _stop.wait(cfg.duration_seconds)
            _stop.set()
        else:
            while not _stop.is_set():
                _stop.wait(1)
    except KeyboardInterrupt:
        _stop.set()

    for w in workers:
        w.join(timeout=5)

    elapsed = time.time() - start
    print(
        f"\nDone. elapsed={elapsed:.0f}s committed={stats.committed} "
        f"deadlocks={stats.deadlocks} errors={stats.errors} "
        f"avg_tps={stats.committed / elapsed if elapsed else 0:.1f}"
    )


if __name__ == "__main__":
    main()
