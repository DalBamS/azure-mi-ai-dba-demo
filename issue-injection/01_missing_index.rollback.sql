/* ==========================================================================
   Issue #1 — ROLLBACK: recreate the leaderboard ranking index
   ========================================================================== */
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_leaderboard_rating'
                 AND object_id = OBJECT_ID(N'dbo.leaderboard'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_leaderboard_rating
        ON dbo.leaderboard (season, rating DESC)
        INCLUDE (player_id, rank_pos, wins, losses);
    PRINT 'Issue #1 rolled back: IX_leaderboard_rating recreated.';
END
ELSE
    PRINT 'Issue #1 rollback: IX_leaderboard_rating already present.';
GO
