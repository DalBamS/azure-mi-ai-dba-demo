/* ==========================================================================
   azure-mi-ai-dba-demo — Seed data generation (parameterized, set-based)
   --------------------------------------------------------------------------
   Target : Azure SQL Managed Instance (T-SQL). Run against the game DB.
   Scale  : Parameterized via SQLCMD variables. Defaults below (:setvar) are
            used for a direct `sqlcmd -i` run; the wrapper (scripts\seed.ps1)
            overrides them with `-v` (which takes precedence over :setvar).
   Safety : Idempotent-ish — seeds ONLY when dbo.players is empty, unless you
            pass -v Force=1. Assumes fresh IDENTITY (player_id = 1..N) when
            seeding child tables. To re-seed, truncate first (see seed.ps1 -Reset).
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
    PRINT 'Seed skipped: dbo.players already contains data. Pass -v Force=1 (or seed.ps1 -Reset) to re-seed.';
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
INSERT dbo.players (username, region, level, status, created_at, last_login_at)
SELECT CONCAT(N'player', n),
       CHOOSE(1 + ABS(CHECKSUM(NEWID())) % 5, 'KR','JP','NA','EU','SEA'),
       1 + ABS(CHECKSUM(NEWID())) % 60,
       CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 96 THEN 1 ELSE 2 END,
       DATEADD(DAY,    -(ABS(CHECKSUM(NEWID())) % 365),   SYSUTCDATETIME()),
       DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % 43200), SYSUTCDATETIME())
FROM Nums;
PRINT CONCAT('  players inserted: ', @@ROWCOUNT);
GO

/* currency_ledger — 3 currency types per player (updatable balances) */
DECLARE @players INT = (SELECT COUNT(*) FROM dbo.players);
;WITH L0 AS (SELECT c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
      L1 AS (SELECT 1 c FROM L0 a CROSS JOIN L0 b),
      L2 AS (SELECT 1 c FROM L1 a CROSS JOIN L1 b),
      L3 AS (SELECT 1 c FROM L2 a CROSS JOIN L1 b),
      L4 AS (SELECT 1 c FROM L3 a CROSS JOIN L2 b),
      Nums AS (SELECT TOP (@players) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM L4)
INSERT dbo.currency_ledger (player_id, currency_type, balance)
SELECT p.n, c.ct, ABS(CHECKSUM(NEWID())) % 1000000
FROM Nums p
CROSS JOIN (VALUES (CAST(1 AS TINYINT)), (2), (3)) c(ct);
PRINT CONCAT('  currency_ledger inserted: ', @@ROWCOUNT);
GO

/* inventory — item_id 1..ItemsPerPlayer per player (hot table) */
DECLARE @players INT = (SELECT COUNT(*) FROM dbo.players);
DECLARE @itemsPerPlayer INT = CONVERT(INT, N'$(SeedItemsPerPlayer)');
;WITH L0 AS (SELECT c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
      L1 AS (SELECT 1 c FROM L0 a CROSS JOIN L0 b),
      L2 AS (SELECT 1 c FROM L1 a CROSS JOIN L1 b),
      L3 AS (SELECT 1 c FROM L2 a CROSS JOIN L1 b),
      L4 AS (SELECT 1 c FROM L3 a CROSS JOIN L2 b),
      P AS (SELECT TOP (@players)        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM L4),
      I AS (SELECT TOP (@itemsPerPlayer) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM L4)
INSERT dbo.inventory (player_id, item_id, quantity)
SELECT p.n, i.n, 1 + ABS(CHECKSUM(NEWID())) % 99
FROM P p CROSS JOIN I i;
PRINT CONCAT('  inventory inserted: ', @@ROWCOUNT);
GO

/* matches — one participation row per match (match_id = n) */
DECLARE @players INT = (SELECT COUNT(*) FROM dbo.players);
DECLARE @matches INT = CONVERT(INT, N'$(SeedMatches)');
;WITH L0 AS (SELECT c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
      L1 AS (SELECT 1 c FROM L0 a CROSS JOIN L0 b),
      L2 AS (SELECT 1 c FROM L1 a CROSS JOIN L1 b),
      L3 AS (SELECT 1 c FROM L2 a CROSS JOIN L1 b),
      L4 AS (SELECT 1 c FROM L3 a CROSS JOIN L2 b),
      Nums AS (SELECT TOP (@matches) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM L4)
INSERT dbo.matches (match_id, player_id, mode, score, result, mmr_change, played_at)
SELECT n,
       1 + ABS(CHECKSUM(NEWID())) % @players,
       CHOOSE(1 + ABS(CHECKSUM(NEWID())) % 4, 'solo','duo','squad','ranked'),
       ABS(CHECKSUM(NEWID())) % 5000,
       CASE ABS(CHECKSUM(NEWID())) % 10 WHEN 0 THEN 2 WHEN 1 THEN 2
            ELSE (ABS(CHECKSUM(NEWID())) % 2) END,               -- ~win/loss with some draws
       -30 + ABS(CHECKSUM(NEWID())) % 61,                        -- mmr change [-30, +30]
       DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % 129600), SYSUTCDATETIME()) -- last ~90 days
FROM Nums;
PRINT CONCAT('  matches inserted: ', @@ROWCOUNT);
GO

/* leaderboard — derived aggregate per player for the season */
DECLARE @season SMALLINT = CONVERT(SMALLINT, N'$(SeedSeason)');
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
