"""Game transaction implementations for the load driver.

Three transaction types make up the steady game workload mix:

* currency_transfer  - moves currency between two players (currency_ledger).
                       Locks the two balance rows in ascending player_id order
                       so *normal* load does not deadlock; issue-injection #2
                       supplies the opposing-order variant to force deadlocks.
* inventory_update   - increments/decrements an item quantity (hot table).
* ranking_query      - Top-N leaderboard read (uses IX_leaderboard_rating;
                       issue-injection #1 drops it to force a full scan).

All statements are parameterized (no string concatenation) — the SQL-injection
demo (M / issue #6) lives in issue-injection, deliberately isolated.
"""

from __future__ import annotations

import random

import pyodbc

GOLD = 1  # currency_type


def currency_transfer(conn: pyodbc.Connection, player_count: int) -> None:
    a = random.randint(1, player_count)
    b = random.randint(1, player_count)
    if a == b:
        b = (b % player_count) + 1
    low, high = (a, b) if a < b else (b, a)
    amount = random.randint(1, 100)

    cur = conn.cursor()
    try:
        # Debit the lower player_id first (consistent lock order).
        cur.execute(
            "UPDATE dbo.currency_ledger "
            "SET balance = balance - ?, updated_at = SYSUTCDATETIME() "
            "WHERE player_id = ? AND currency_type = ? AND balance >= ?;",
            amount, low, GOLD, amount,
        )
        cur.execute(
            "UPDATE dbo.currency_ledger "
            "SET balance = balance + ?, updated_at = SYSUTCDATETIME() "
            "WHERE player_id = ? AND currency_type = ?;",
            amount, high, GOLD,
        )
        conn.commit()
    except pyodbc.Error:
        conn.rollback()
        raise


def inventory_update(conn: pyodbc.Connection, player_count: int, items_per_player: int) -> None:
    player_id = random.randint(1, player_count)
    item_id = random.randint(1, max(1, items_per_player))
    delta = random.choice([-3, -1, 1, 1, 2, 5])

    cur = conn.cursor()
    try:
        cur.execute(
            "UPDATE dbo.inventory "
            "SET quantity = CASE WHEN quantity + ? < 0 THEN 0 ELSE quantity + ? END, "
            "    updated_at = SYSUTCDATETIME() "
            "WHERE player_id = ? AND item_id = ?;",
            delta, delta, player_id, item_id,
        )
        conn.commit()
    except pyodbc.Error:
        conn.rollback()
        raise


def ranking_query(conn: pyodbc.Connection, season: int, top_n: int = 100) -> int:
    cur = conn.cursor()
    cur.execute(
        "SELECT TOP (?) player_id, rating, rank_pos "
        "FROM dbo.leaderboard WHERE season = ? "
        "ORDER BY rating DESC;",
        top_n, season,
    )
    rows = cur.fetchall()
    return len(rows)
