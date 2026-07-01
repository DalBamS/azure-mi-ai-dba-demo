/* A — Remediate: recreate the missing ranking index.
   Human approval required before running. Equivalent to issue rollback #1.
*/
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.leaderboard')
                 AND name = N'IX_leaderboard_rating')
BEGIN
    CREATE NONCLUSTERED INDEX IX_leaderboard_rating
        ON dbo.leaderboard (season, rating DESC)
        INCLUDE (player_id, rank_pos, wins, losses);
    PRINT 'Remediation applied: IX_leaderboard_rating created.';
END
ELSE
    PRINT 'No-op: IX_leaderboard_rating already exists.';
GO
