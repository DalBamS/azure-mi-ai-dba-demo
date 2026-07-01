/* ==========================================================================
   Issue #1 — Missing index: leaderboard ranking full scan
   --------------------------------------------------------------------------
   Effect : Drops IX_leaderboard_rating so Top-N ranking queries
            (ORDER BY rating DESC) fall back to a full clustered-index scan.
   Demo   : A (slow query diagnosis / index recommendation).
   Rollback: 01_missing_index.rollback.sql  (recreates the index)
   ========================================================================== */
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_leaderboard_rating'
             AND object_id = OBJECT_ID(N'dbo.leaderboard'))
BEGIN
    DROP INDEX IX_leaderboard_rating ON dbo.leaderboard;
    PRINT 'Issue #1 injected: dropped IX_leaderboard_rating (ranking queries now scan).';
END
ELSE
    PRINT 'Issue #1: IX_leaderboard_rating already absent.';
GO

/* Reproduce the symptom (observe the scan in the actual plan): */
-- SET STATISTICS IO ON;
-- SELECT TOP (100) player_id, rating, rank_pos
-- FROM dbo.leaderboard WHERE season = 1 ORDER BY rating DESC;
