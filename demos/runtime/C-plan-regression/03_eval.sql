/* C — Eval: benchmark current proc path.
*/
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

EXEC dbo.usp_matches_summary @maxPlayer = 100000;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SELECT CASE
           WHEN OBJECT_ID(N'dbo.usp_matches_summary', N'P') IS NOT NULL THEN 'PASS: repro proc exists'
           ELSE 'FAIL: repro proc missing'
       END AS eval_proc_presence;
GO
