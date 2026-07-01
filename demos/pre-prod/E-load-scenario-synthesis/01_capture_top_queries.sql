/* ==========================================================================
   E — Capture: top-query shape & mix from Query Store (read-only)
   --------------------------------------------------------------------------
   Purpose : Ground the synthesized load profile in REAL production shape by
             reading Query Store: which query families dominate and in what
             proportion (ranking / currency / inventory / other).
   Safety  : Read-only. Suitable for MCP read-only execution.
   Prereq  : Query Store ON for the game DB (ALTER DATABASE ... SET QUERY_STORE = ON).
             Background load (workload\game-driver) has been running so QS has data.
   Output  : (1) Top queries by execution count, (2) category share summary
             used by 02_synthesize_profile.py to sanity-check the requested mix.
   ========================================================================== */
SET NOCOUNT ON;
GO

PRINT '1) Top queries by execution count (last 24h of collected QS runtime stats).';
SELECT TOP (25)
       q.query_id,
       qt.query_sql_text,
       SUM(rs.count_executions)                              AS executions,
       CAST(SUM(rs.count_executions * rs.avg_duration) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS decimal(18,2)) AS avg_duration_ms,
       CAST(SUM(rs.count_executions * rs.avg_logical_io_reads) / NULLIF(SUM(rs.count_executions), 0) AS decimal(18,1))  AS avg_logical_reads
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan AS p        ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY q.query_id, qt.query_sql_text
ORDER BY executions DESC;
GO

PRINT '2) Category mix share (%) — the baseline the requested profile is compared against.';
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
)
SELECT category,
       executions,
       CAST(100.0 * executions / NULLIF(SUM(executions) OVER (), 0) AS decimal(5,1)) AS share_pct
FROM categorized
ORDER BY executions DESC;
GO
