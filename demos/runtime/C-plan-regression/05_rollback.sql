/* C — Rollback/cleanup for demo-specific procedures.
   Inline instead of SQLCMD :r so it works from any current directory.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.usp_matches_summary_stable_example', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_matches_summary_stable_example;
GO

IF OBJECT_ID(N'dbo.usp_matches_summary', N'P') IS NOT NULL
BEGIN
    EXEC sp_recompile N'dbo.usp_matches_summary';
    DROP PROCEDURE dbo.usp_matches_summary;
    PRINT 'C cleanup: dropped dbo.usp_matches_summary and flushed its plan.';
END
ELSE
    PRINT 'C cleanup: dbo.usp_matches_summary already absent.';
GO
