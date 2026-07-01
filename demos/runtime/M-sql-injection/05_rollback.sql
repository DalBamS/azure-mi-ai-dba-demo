/* M — Rollback/cleanup.
   Inline instead of SQLCMD :r so it works from any current directory.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.usp_search_players_safe_example', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_search_players_safe_example;
GO

IF OBJECT_ID(N'dbo.usp_search_players_unsafe', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_search_players_unsafe;
    PRINT 'M cleanup: dropped dbo.usp_search_players_unsafe.';
END
ELSE
    PRINT 'M cleanup: dbo.usp_search_players_unsafe already absent.';
GO
