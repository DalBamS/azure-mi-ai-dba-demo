/* A — Eval: benchmark the ranking query.
   Run before and after remediation. Capture elapsed time and logical reads from Messages.
*/
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

DECLARE @i int = 0;
WHILE @i < 5
BEGIN
    SELECT TOP (100) player_id, rating, rank_pos, wins, losses
    FROM dbo.leaderboard
    WHERE season = 1
    ORDER BY rating DESC;
    SET @i += 1;
END
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SELECT CASE
           WHEN EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.leaderboard') AND name = N'IX_leaderboard_rating')
           THEN 'PASS: IX_leaderboard_rating exists'
           ELSE 'FAIL: IX_leaderboard_rating missing'
       END AS eval_index_presence;
GO
