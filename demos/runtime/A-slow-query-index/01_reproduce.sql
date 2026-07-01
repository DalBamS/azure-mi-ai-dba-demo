/* A — Reproduce: slow ranking query after missing index injection.
   Prereq: issue-injection\01_missing_index.sql has dropped IX_leaderboard_rating.
*/
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

SELECT TOP (100) player_id, rating, rank_pos, wins, losses
FROM dbo.leaderboard
WHERE season = 1
ORDER BY rating DESC;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
