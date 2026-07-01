/* A — Rollback/cleanup.
   The remediation restores the normal schema, so rollback is the same safety check.
   Inline instead of SQLCMD :r so it works from any current directory.
*/
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_leaderboard_rating'
                 AND object_id = OBJECT_ID(N'dbo.leaderboard'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_leaderboard_rating
        ON dbo.leaderboard (season, rating DESC)
        INCLUDE (player_id, rank_pos, wins, losses);
    PRINT 'A cleanup: IX_leaderboard_rating recreated.';
END
ELSE
    PRINT 'A cleanup: IX_leaderboard_rating already present.';
GO
