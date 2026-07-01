/* ==========================================================================
   Issue #5 — Runaway query (cartesian / join explosion)
   --------------------------------------------------------------------------
   Effect : A CROSS JOIN across matches x matches x players produces an
            astronomically large row set with a non-sargable predicate. The
            query runs effectively unbounded -> a "runaway" the DBA must find
            and stop.
   Demo   : runtime runaway-query detection & kill.
   WARNING: Isolated demo MI ONLY. This will run for a very long time and
            consume CPU. Stop it deliberately (see rollback for how to KILL).
   Rollback: 05_runaway_query.rollback.sql (find + KILL guidance)
   ========================================================================== */
SET NOCOUNT ON;
GO

PRINT 'Issue #5: starting a runaway cartesian query (KILL it from another session).';

SELECT COUNT_BIG(*) AS runaway_rows
FROM dbo.matches AS m1
CROSS JOIN dbo.matches AS m2
CROSS JOIN dbo.players AS p
WHERE (m1.score * 1.0) / NULLIF(m2.score, 0) > 0.5   -- non-sargable, prevents shortcut
OPTION (MAXDOP 1);

PRINT 'Issue #5 completed (if you see this, the dataset was small enough to finish).';
GO
