/* ==========================================================================
   Issue #6 — ROLLBACK: remove the vulnerable proc
   ========================================================================== */
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.usp_search_players_unsafe', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_search_players_unsafe;
    PRINT 'Issue #6 rolled back: dropped dbo.usp_search_players_unsafe.';
END
ELSE
    PRINT 'Issue #6 rollback: dbo.usp_search_players_unsafe already absent.';
GO
