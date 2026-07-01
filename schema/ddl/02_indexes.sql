/* ==========================================================================
   azure-mi-ai-dba-demo — Game schema: tuning indexes
   --------------------------------------------------------------------------
   Target : Azure SQL Managed Instance (T-SQL)
   Safety : IDEMPOTENT — safe to re-run.
   Role   : "정상" 인덱스 세트. issue-injection 이 일부를 DROP 하여 문제를 유발하고,
            롤백은 이 파일을 다시 실행해 복구한다.
   ========================================================================== */

SET NOCOUNT ON;
GO

/* players: 지역별 조회 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_players_region' AND object_id = OBJECT_ID(N'dbo.players'))
    CREATE NONCLUSTERED INDEX IX_players_region
        ON dbo.players (region) INCLUDE (level, status);
GO

/* inventory: 아이템별 역방향 조회 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inventory_item' AND object_id = OBJECT_ID(N'dbo.inventory'))
    CREATE NONCLUSTERED INDEX IX_inventory_item
        ON dbo.inventory (item_id) INCLUDE (quantity);
GO

/* matches: 플레이어별 집계(리더보드 소스) */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_matches_player' AND object_id = OBJECT_ID(N'dbo.matches'))
    CREATE NONCLUSTERED INDEX IX_matches_player
        ON dbo.matches (player_id) INCLUDE (score, result, mmr_change);
GO

/* matches: 최근 기간 조회 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_matches_played_at' AND object_id = OBJECT_ID(N'dbo.matches'))
    CREATE NONCLUSTERED INDEX IX_matches_played_at
        ON dbo.matches (played_at);
GO

/* --------------------------------------------------------------------------
   leaderboard: Top-N 랭킹 조회용 핵심 인덱스.
   ⚠ issue #1 (missing index) 이 이 인덱스를 DROP → rating 정렬 시 풀스캔.
   -------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_leaderboard_rating' AND object_id = OBJECT_ID(N'dbo.leaderboard'))
    CREATE NONCLUSTERED INDEX IX_leaderboard_rating
        ON dbo.leaderboard (season, rating DESC) INCLUDE (player_id, rank_pos, wins, losses);
GO

PRINT '02_indexes.sql: tuning indexes ensured.';
GO
