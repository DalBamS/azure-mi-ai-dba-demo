/* ==========================================================================
   Issue #6 — SQL Injection (vulnerable dynamic SQL)
   --------------------------------------------------------------------------
   Effect : Creates a DELIBERATELY VULNERABLE search proc that concatenates
            user input into dynamic SQL. Used to demonstrate detection &
            diagnosis of SQL-injection attempts.
   Demo   : M (SQL injection detection / diagnosis).
   WARNING: ISOLATED DEMO MI ONLY. Never deploy this pattern to production.
            The injection examples run in the safe game DB context.
   Rollback: 06_sql_injection.rollback.sql (drops the vulnerable proc)
   ========================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_search_players_unsafe
    @name NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    -- !! VULNERABLE ON PURPOSE: input is concatenated, not parameterized. !!
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT player_id, username, region FROM dbo.players '
      + N'WHERE username LIKE ''%' + @name + N'%'';';
    EXEC (@sql);
END
GO

PRINT 'Issue #6 injected: dbo.usp_search_players_unsafe (vulnerable) created.';
PRINT 'Benign : EXEC dbo.usp_search_players_unsafe @name = N''player1'';';
PRINT 'Attack : EXEC dbo.usp_search_players_unsafe @name = N'''' OR 1=1 --'';';
PRINT 'Recon  : EXEC dbo.usp_search_players_unsafe @name = N''''''; SELECT name FROM sys.tables; --'';';

/* --------------------------------------------------------------------------
   The safe form (what the fix / AI recommendation should produce):

   CREATE OR ALTER PROCEDURE dbo.usp_search_players
       @name NVARCHAR(100)
   AS
   BEGIN
       SET NOCOUNT ON;
       SELECT player_id, username, region
       FROM dbo.players
       WHERE username LIKE N'%' + @name + N'%';   -- parameterized, no EXEC
   END
   -------------------------------------------------------------------------- */
GO
