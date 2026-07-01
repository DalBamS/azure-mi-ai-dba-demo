/* ==========================================================================
   Issue #3 — ROLLBACK: remove the plan-regression proc and flush its plan
   ========================================================================== */
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.usp_matches_summary', N'P') IS NOT NULL
BEGIN
    EXEC sp_recompile N'dbo.usp_matches_summary';
    DROP PROCEDURE dbo.usp_matches_summary;
    PRINT 'Issue #3 rolled back: dropped dbo.usp_matches_summary and flushed its plan.';
END
ELSE
    PRINT 'Issue #3 rollback: dbo.usp_matches_summary already absent.';
GO
