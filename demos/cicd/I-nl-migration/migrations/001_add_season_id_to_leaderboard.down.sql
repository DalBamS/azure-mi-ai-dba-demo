/* ==========================================================================
   Demo I — Migration 001 DOWN: leaderboard.season_id 롤백
   --------------------------------------------------------------------------
   Reverses 001_add_season_id_to_leaderboard.up.sql. IDEMPOTENT.
   순서: 인덱스 → FK → 컬럼 → (seasons 는 데이터 보존 위해 기본 유지).
   ========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* 1) 신규 인덱스 제거 */
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_leaderboard_season_id_rating'
             AND object_id = OBJECT_ID(N'dbo.leaderboard'))
BEGIN
    DROP INDEX IX_leaderboard_season_id_rating ON dbo.leaderboard;
    PRINT '001 down: IX_leaderboard_season_id_rating dropped.';
END
GO

/* 2) FK 제거 */
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_leaderboard_seasons')
BEGIN
    ALTER TABLE dbo.leaderboard DROP CONSTRAINT FK_leaderboard_seasons;
    PRINT '001 down: FK_leaderboard_seasons dropped.';
END
GO

/* 3) season_id 컬럼 제거 */
IF COL_LENGTH(N'dbo.leaderboard', N'season_id') IS NOT NULL
BEGIN
    ALTER TABLE dbo.leaderboard DROP COLUMN season_id;
    PRINT '001 down: leaderboard.season_id dropped.';
END
GO

/* 4) seasons 테이블: 데이터 손실 방지를 위해 기본은 보존.
      완전 원복이 필요하면 아래 주석을 해제(수동 승인 후).
      -- IF OBJECT_ID(N'dbo.seasons', N'U') IS NOT NULL DROP TABLE dbo.seasons;
*/
PRINT '001 down: complete. (dbo.seasons preserved by default)';
GO
