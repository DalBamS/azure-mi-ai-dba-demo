/* ==========================================================================
   Issue #3 — Plan regression (parameter sniffing)
   --------------------------------------------------------------------------
   Effect : Creates a proc whose plan is sensitive to its parameter, then
            primes the cache with an ATYPICAL tiny parameter so a skewed plan
            (tuned for ~1 row) gets cached. Subsequent typical calls with a
            large parameter reuse that bad plan -> regression.
   Note   : The game load driver connects like the production C++/MSOLEDBSQL
            client (ARITHABORT OFF), which keeps a *separate* plan-cache entry
            from SSMS (ARITHABORT ON) -- the classic "fast in SSMS, slow in
            app" angle. Reproduce the app path with the driver running.
   Demo   : C (post-patch plan regression response).
   Rollback: 03_plan_regression.rollback.sql
   ========================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_matches_summary
    @maxPlayer BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT player_id, COUNT(*) AS matches_played, SUM(score) AS total_score
    FROM dbo.matches
    WHERE player_id <= @maxPlayer
    GROUP BY player_id
    ORDER BY total_score DESC;
END
GO

-- Flush this proc's cached plans, then sniff a tiny parameter to cache a
-- plan optimized for ~1 row.
EXEC sp_recompile N'dbo.usp_matches_summary';
GO
EXEC dbo.usp_matches_summary @maxPlayer = 1;   -- caches the skewed plan
GO

PRINT 'Issue #3 injected: dbo.usp_matches_summary cached a tiny-parameter plan.';
PRINT 'Now typical calls regress, e.g.:  EXEC dbo.usp_matches_summary @maxPlayer = 100000;';
GO
