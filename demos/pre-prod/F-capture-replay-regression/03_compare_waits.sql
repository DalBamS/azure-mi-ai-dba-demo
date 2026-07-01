/* ==========================================================================
   F — Compare: baseline vs replay wait stats & duration (regression check)
   --------------------------------------------------------------------------
   Purpose : The AI version of a DEA regression report - quantify what changed
             between a BASELINE window and a REPLAY window using Query Store.
   Safety  : Read-only.
   Prereq  : Query Store ON with wait stats capture (default). Record the UTC
             start/end of each window (from 02_replay.md) into the variables.
   Output  : (1) duration/CPU/reads delta by query, (2) wait-category delta.
             Positive delta = replay is SLOWER than baseline (regression).
   ========================================================================== */
SET NOCOUNT ON;
GO

DECLARE @base_start  datetime2 = DATEADD(HOUR, -3, SYSUTCDATETIME());
DECLARE @base_end    datetime2 = DATEADD(HOUR, -2, SYSUTCDATETIME());
DECLARE @replay_start datetime2 = DATEADD(HOUR, -1, SYSUTCDATETIME());
DECLARE @replay_end   datetime2 = SYSUTCDATETIME();

PRINT '1) Per-query regression: avg duration / CPU / logical reads (replay - baseline).';
;WITH stats AS
(
    SELECT q.query_id,
           qt.query_sql_text,
           CASE WHEN rsi.start_time BETWEEN @base_start AND @base_end THEN 'baseline'
                WHEN rsi.start_time BETWEEN @replay_start AND @replay_end THEN 'replay' END AS window_tag,
           rs.count_executions,
           rs.avg_duration,
           rs.avg_cpu_time,
           rs.avg_logical_io_reads
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    JOIN sys.query_store_plan AS p        ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE rsi.start_time BETWEEN @base_start AND @base_end
       OR rsi.start_time BETWEEN @replay_start AND @replay_end
),
agg AS
(
    SELECT query_id, query_sql_text, window_tag,
           SUM(count_executions)                                                          AS execs,
           SUM(count_executions * avg_duration)        / NULLIF(SUM(count_executions),0) / 1000.0 AS avg_duration_ms,
           SUM(count_executions * avg_cpu_time)        / NULLIF(SUM(count_executions),0) / 1000.0 AS avg_cpu_ms,
           SUM(count_executions * avg_logical_io_reads)/ NULLIF(SUM(count_executions),0)          AS avg_reads
    FROM stats
    GROUP BY query_id, query_sql_text, window_tag
),
pivoted AS
(
    SELECT query_id,
           MAX(query_sql_text) AS query_sql_text,
           MAX(CASE WHEN window_tag='baseline' THEN avg_duration_ms END) AS base_ms,
           MAX(CASE WHEN window_tag='replay'   THEN avg_duration_ms END) AS replay_ms,
           MAX(CASE WHEN window_tag='baseline' THEN avg_reads END)       AS base_reads,
           MAX(CASE WHEN window_tag='replay'   THEN avg_reads END)       AS replay_reads
    FROM agg
    GROUP BY query_id
)
SELECT TOP (25)
       query_id,
       CAST(base_ms   AS decimal(18,2)) AS base_ms,
       CAST(replay_ms AS decimal(18,2)) AS replay_ms,
       CAST(replay_ms - base_ms AS decimal(18,2)) AS duration_delta_ms,
       CAST(replay_reads - base_reads AS decimal(18,1)) AS reads_delta,
       SUBSTRING(query_sql_text, 1, 120) AS query_preview
FROM pivoted
WHERE base_ms IS NOT NULL AND replay_ms IS NOT NULL
ORDER BY (replay_ms - base_ms) DESC;   -- biggest regressions first
GO

PRINT '2) Wait-category shift (replay - baseline), total wait ms.';
;WITH w AS
(
    SELECT ws.wait_category_desc,
           CASE WHEN rsi.start_time BETWEEN @base_start AND @base_end THEN 'baseline'
                WHEN rsi.start_time BETWEEN @replay_start AND @replay_end THEN 'replay' END AS window_tag,
           ws.total_query_wait_time_ms
    FROM sys.query_store_wait_stats AS ws
    JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = ws.runtime_stats_interval_id
    WHERE rsi.start_time BETWEEN @base_start AND @base_end
       OR rsi.start_time BETWEEN @replay_start AND @replay_end
)
SELECT wait_category_desc,
       SUM(CASE WHEN window_tag='baseline' THEN total_query_wait_time_ms ELSE 0 END) AS baseline_wait_ms,
       SUM(CASE WHEN window_tag='replay'   THEN total_query_wait_time_ms ELSE 0 END) AS replay_wait_ms,
       SUM(CASE WHEN window_tag='replay'   THEN total_query_wait_time_ms ELSE 0 END)
     - SUM(CASE WHEN window_tag='baseline' THEN total_query_wait_time_ms ELSE 0 END) AS wait_delta_ms
FROM w
GROUP BY wait_category_desc
HAVING SUM(total_query_wait_time_ms) > 0
ORDER BY wait_delta_ms DESC;
GO
