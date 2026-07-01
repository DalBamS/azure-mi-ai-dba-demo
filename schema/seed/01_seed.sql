/* ==========================================================================
   azure-mi-ai-dba-demo — Seed data generation (parameterized, set-based)
   --------------------------------------------------------------------------
   Target : Azure SQL Managed Instance (T-SQL). Run against the game DB.
   Scale  : Parameterized via SQLCMD variables. Defaults below (:setvar) are
            used for a direct `sqlcmd -i` run; the wrapper (scripts\seed.ps1)
            overrides them with `-v` (which takes precedence over :setvar).
   Safety : Idempotent-ish — each table batch skips when that table already
            contains data and Force=0. To re-seed cleanly, use seed.ps1 -Reset.
            Child tables source player_id from dbo.players (not a 1..N tally),
            so they stay FK-safe even if IDENTITY was consumed by a prior
            failed/retried seed (player_id may start above 1).
   Random : Volatile NEWID() is never used inside a CHOOSE index argument
            (it can be re-evaluated and yield out-of-range -> NULL). Categorical
            columns use a deterministic row number; numeric randoms use
            (CHECKSUM(NEWID()) & 0x7FFFFFFF) so the value is always 0..2^31-1
            (plain ABS(CHECKSUM(...)) can return a negative at INT_MIN).
   Profiles (set by scripts\seed.ps1 from SEED_PROFILE):
       default : SeedPlayers=100000 ItemsPerPlayer=20 Matches=200000
       smoke   : SeedPlayers=1000   ItemsPerPlayer=10 Matches=5000
   ========================================================================== */

:setvar SeedPlayers        "100000"
:setvar SeedItemsPerPlayer "20"
:setvar SeedMatches        "200000"
:setvar SeedSeason         "1"
:setvar Force              "0"

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @players        INT      = CONVERT(INT, N'$(SeedPlayers)');
DECLARE @itemsPerPlayer INT      = CONVERT(INT, N'$(SeedItemsPerPlayer)');
DECLARE @matches        INT      = CONVERT(INT, N'$(SeedMatches)');
DECLARE @season         SMALLINT = CONVERT(SMALLINT, N'$(SeedSeason)');
DECLARE @force          BIT      = CONVERT(BIT, N'$(Force)');

IF EXISTS (SELECT 1 FROM dbo.players) AND @force = 0
BEGIN
    PRINT '  players skipped: table already contains data. Use seed.ps1 -Reset to re-seed.';
    RETURN;
END;

PRINT CONCAT('Seeding: players=', @players, ' itemsPerPlayer=', @itemsPerPlayer,
             ' matches=', @matches, ' season=', @season);

/* --------------------------------------------------------------------------
   Numbers/tally CTE — generates up to ~4 billion rows without a table.
   -------------------------------------------------------------------------- */
;WITH L0 AS (SELECT c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),   -- 10
      L1 AS (SELECT 1 c FROM L0 a CROSS JOIN L0 b),                                  -- 100
      L2 AS (SELECT 1 c FROM L1 a CROSS JOIN L1 b),                                  -- 10^4
      L3 AS (SELECT 1 c FROM L2 a CROSS JOIN L1 b),                                  -- 10^6
      L4 AS (SELECT 1 c FROM L3 a CROSS JOIN L2 b),                                  -- 10^10
      Nums AS (SELECT TOP (@players) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM L4)
INSERT dbo.players (username, email, region, level, status, created_at, last_login_at)
SELECT CONCAT(N'player', n),
       CONCAT(N'player', n, N'@example.com'),                    -- synthetic (not PII), for DDM demo
       CHOOSE(1 + CONVERT(INT, n % 5), 'KR','JP','NA','EU','SEA'),  -- deterministic, even split
       1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 60,
       CASE WHEN (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 < 96 THEN 1 ELSE 2 END,
       DATEADD(DAY,    -((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 365),   SYSUTCDATETIME()),
       DATEADD(MINUTE, -((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 43200), SYSUTCDATETIME())
FROM Nums;
PRINT CONCAT('  players inserted: ', @@ROWCOUNT);
GO

/* currency_ledger — 3 currency types per player (updatable balances) */
DECLARE @force BIT = CONVERT(BIT, N'$(Force)');

IF EXISTS (SELECT 1 FROM dbo.currency_ledger) AND @force = 0
BEGIN
    PRINT '  currency_ledger skipped: table already contains data.';
    RETURN;
END;

-- Source player_id from the real dbo.players rows (FK-safe regardless of IDENTITY start).
INSERT dbo.currency_ledger (player_id, currency_type, balance)
SELECT p.player_id, c.ct, (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1000000
FROM dbo.players p
CROSS JOIN (VALUES (CAST(1 AS TINYINT)), (2), (3)) c(ct);
PRINT CONCAT('  currency_ledger inserted: ', @@ROWCOUNT);
GO

/* inventory — item_id 1..ItemsPerPlayer per player (hot table) */
DECLARE @itemsPerPlayer INT = CONVERT(INT, N'$(SeedItemsPerPlayer)');
DECLARE @force BIT = CONVERT(BIT, N'$(Force)');

IF EXISTS (SELECT 1 FROM dbo.inventory) AND @force = 0
BEGIN
    PRINT '  inventory skipped: table already contains data.';
    RETURN;
END;

-- player_id from real dbo.players; item_id from a small 1..@itemsPerPlayer tally.
;WITH L0 AS (SELECT c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
      L1 AS (SELECT 1 c FROM L0 a CROSS JOIN L0 b),
      L2 AS (SELECT 1 c FROM L1 a CROSS JOIN L1 b),
      L3 AS (SELECT 1 c FROM L2 a CROSS JOIN L1 b),
      L4 AS (SELECT 1 c FROM L3 a CROSS JOIN L2 b),
      I AS (SELECT TOP (@itemsPerPlayer) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM L4)
INSERT dbo.inventory (player_id, item_id, quantity)
SELECT p.player_id, i.n, 1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 99
FROM dbo.players p CROSS JOIN I i;
PRINT CONCAT('  inventory inserted: ', @@ROWCOUNT);
GO

/* matches — one participation row per match (match_id = n) */
DECLARE @players INT = (SELECT COUNT(*) FROM dbo.players);
DECLARE @minPlayer BIGINT = (SELECT MIN(player_id) FROM dbo.players);
DECLARE @matches INT = CONVERT(INT, N'$(SeedMatches)');
DECLARE @force BIT = CONVERT(BIT, N'$(Force)');

IF EXISTS (SELECT 1 FROM dbo.matches) AND @force = 0
BEGIN
    PRINT '  matches skipped: table already contains data.';
    RETURN;
END;

;WITH L0 AS (SELECT c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
      L1 AS (SELECT 1 c FROM L0 a CROSS JOIN L0 b),
      L2 AS (SELECT 1 c FROM L1 a CROSS JOIN L1 b),
      L3 AS (SELECT 1 c FROM L2 a CROSS JOIN L1 b),
      L4 AS (SELECT 1 c FROM L3 a CROSS JOIN L2 b),
      Nums AS (SELECT TOP (@matches) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM L4)
INSERT dbo.matches (match_id, player_id, mode, score, result, mmr_change, played_at)
SELECT n,
       @minPlayer + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % @players,   -- map onto real player_id range
       CHOOSE(1 + CONVERT(INT, n % 4), 'solo','duo','squad','ranked'),  -- deterministic mode
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 5000,
       CASE (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 10 WHEN 0 THEN 2 WHEN 1 THEN 2
            ELSE ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 2) END,     -- ~win/loss with some draws
       -30 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 61,              -- mmr change [-30, +30]
       DATEADD(MINUTE, -((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 129600), SYSUTCDATETIME()) -- last ~90 days
FROM Nums;
PRINT CONCAT('  matches inserted: ', @@ROWCOUNT);
GO

/* leaderboard — derived aggregate per player for the season */
DECLARE @season SMALLINT = CONVERT(SMALLINT, N'$(SeedSeason)');
DECLARE @force BIT = CONVERT(BIT, N'$(Force)');

IF EXISTS (SELECT 1 FROM dbo.leaderboard) AND @force = 0
BEGIN
    PRINT '  leaderboard skipped: table already contains data.';
    RETURN;
END;

INSERT dbo.leaderboard (season, player_id, rating, wins, losses, rank_pos)
SELECT @season,
       m.player_id,
       1000 + SUM(m.mmr_change),
       SUM(CASE WHEN m.result = 1 THEN 1 ELSE 0 END),
       SUM(CASE WHEN m.result = 0 THEN 1 ELSE 0 END),
       ROW_NUMBER() OVER (ORDER BY 1000 + SUM(m.mmr_change) DESC)
FROM dbo.matches m
GROUP BY m.player_id;
PRINT CONCAT('  leaderboard inserted: ', @@ROWCOUNT);
GO

PRINT '01_seed.sql: seeding complete.';
GO
