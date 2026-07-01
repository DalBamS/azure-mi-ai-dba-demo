/* ==========================================================================
   G — Rollback/cleanup: remove the sample anti-pattern object
   ========================================================================== */
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.usp_preflight_badexample', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_preflight_badexample;
    PRINT 'G cleanup: dropped dbo.usp_preflight_badexample.';
END
ELSE
    PRINT 'G cleanup: dbo.usp_preflight_badexample already absent.';
GO
