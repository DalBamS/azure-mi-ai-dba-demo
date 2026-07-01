/* B — Rollback/cleanup.
   Drops the reference safe-pattern proc created by 04_safe_pattern.sql so the
   demo leaves no leftover objects (parity with A/C/M cleanup scripts).
   Deadlock-inducing data churn from issue-injection #2 is undone separately by
   issue-injection\02_blocking_deadlock.rollback.sql.
   Inline instead of SQLCMD :r so it works from any current directory.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.usp_transfer_gold_safe_example', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_transfer_gold_safe_example;
    PRINT 'B cleanup: dropped dbo.usp_transfer_gold_safe_example.';
END
ELSE
    PRINT 'B cleanup: dbo.usp_transfer_gold_safe_example already absent.';
GO
