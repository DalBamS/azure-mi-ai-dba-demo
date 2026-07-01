/* C — Reproduce: run typical parameter after tiny-parameter sniffing.
   Prereq: issue-injection\03_plan_regression.sql.
*/
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

EXEC dbo.usp_matches_summary @maxPlayer = 100000;
GO 3

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
