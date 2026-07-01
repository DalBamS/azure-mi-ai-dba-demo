/* ==========================================================================
   E — Eval: does the synthesized mix match real Query Store shares?
   --------------------------------------------------------------------------
   Purpose : Score the profile from 02_synthesize_profile.py against the
             observed production shape (01_capture_top_queries.sql source).
             A good synthetic profile should be within tolerance of reality.
   Safety  : Read-only.
   How     : Paste the requested mix (from profile.example.env) into the three
             @req_* variables, set @tolerance_pp, then run. PASS = every
             category is within +/- tolerance percentage-points of QS share.
   ========================================================================== */
SET NOCOUNT ON;
GO

DECLARE @req_currency_pct  int = 40;   -- WORKLOAD_MIX_CURRENCY_TRANSFER
DECLARE @req_ranking_pct   int = 30;   -- WORKLOAD_MIX_RANKING_QUERY
DECLARE @req_inventory_pct int = 30;   -- WORKLOAD_MIX_INVENTORY_UPDATE
DECLARE @tolerance_pp      int = 15;   -- allowed +/- percentage-point drift

;WITH categorized AS
(
    SELECT SUM(rs.count_executions) AS executions,
           CASE
               WHEN qt.query_sql_text LIKE '%leaderboard%'      THEN 'ranking_query'
               WHEN qt.query_sql_text LIKE '%currency_ledger%'  THEN 'currency_transfer'
               WHEN qt.query_sql_text LIKE '%inventory%'        THEN 'inventory_update'
               ELSE 'other'
           END AS category
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    JOIN sys.query_store_plan AS p        ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE rsi.start_time >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    GROUP BY CASE
               WHEN qt.query_sql_text LIKE '%leaderboard%'      THEN 'ranking_query'
               WHEN qt.query_sql_text LIKE '%currency_ledger%'  THEN 'currency_transfer'
               WHEN qt.query_sql_text LIKE '%inventory%'        THEN 'inventory_update'
               ELSE 'other'
             END
),
observed AS
(
    SELECT category,
           CAST(100.0 * executions / NULLIF(SUM(executions) OVER (), 0) AS decimal(5,1)) AS observed_pct
    FROM categorized
    WHERE category <> 'other'
),
compared AS
(
    SELECT c.category, c.requested_pct,
           COALESCE(o.observed_pct, 0) AS observed_pct,
           ABS(c.requested_pct - COALESCE(o.observed_pct, 0)) AS drift_pp
    FROM (VALUES ('currency_transfer', @req_currency_pct),
                 ('ranking_query',     @req_ranking_pct),
                 ('inventory_update',  @req_inventory_pct)) AS c(category, requested_pct)
    LEFT JOIN observed o ON o.category = c.category
)
SELECT category, requested_pct, observed_pct, drift_pp,
       CASE WHEN drift_pp <= @tolerance_pp THEN 'PASS' ELSE 'CHECK' END AS within_tolerance
FROM compared
ORDER BY category;
GO

PRINT 'Note: CHECK rows mean the synthetic mix diverges from observed load - adjust WORKLOAD_MIX_* or the request, or accept the divergence intentionally (e.g., stress a specific path).';
GO
