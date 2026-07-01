/* ==========================================================================
   azure-mi-ai-dba-demo — Game database Query Store settings
   --------------------------------------------------------------------------
   Target : Azure SQL Managed Instance (T-SQL)
   Run    : against the game database (e.g. gamedb). Connect to that DB first.
   Purpose: Enable Query Store so demo E can capture game workload shape from
            dbo.leaderboard, dbo.currency_ledger, and dbo.inventory queries.
   Safety : IDEMPOTENT — safe to re-run. Re-applies the intended demo options.
   Prereq : Requires ALTER DATABASE permission on the current game database.
   ========================================================================== */

SET NOCOUNT ON;
GO

ALTER DATABASE CURRENT SET QUERY_STORE = ON;
GO

ALTER DATABASE CURRENT SET QUERY_STORE
(
    OPERATION_MODE = READ_WRITE,
    -- Demo setting: capture every game query so short demos do not miss a family.
    -- Production guidance: AUTO is usually preferred to avoid low-value capture.
    QUERY_CAPTURE_MODE = ALL,
    -- Demo setting: 5-minute intervals make short 3-5 minute runs visible sooner.
    -- Production default is typically 60 minutes.
    INTERVAL_LENGTH_MINUTES = 5,
    MAX_STORAGE_SIZE_MB = 1024,
    -- Demo setting: flush every 60 seconds so Query Store reads catch up quickly.
    -- Production default is typically 900 seconds.
    DATA_FLUSH_INTERVAL_SECONDS = 60,
    WAIT_STATS_CAPTURE_MODE = ON,
    MAX_PLANS_PER_QUERY = 200,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30)
);
GO

PRINT '1) Query Store state.';
SELECT actual_state_desc,
       query_capture_mode_desc,
       interval_length_minutes,
       current_storage_size_mb,
       max_storage_size_mb
FROM sys.database_query_store_options;
GO

PRINT '2) Recent game workload category executions (last 1 hour).';
DECLARE @category_counts TABLE
(
    category nvarchar(64) NOT NULL,
    executions bigint NOT NULL
);

INSERT INTO @category_counts (category, executions)
SELECT expected.category,
       COALESCE(observed.executions, 0) AS executions
FROM (VALUES
         (N'ranking_query'),
         (N'currency_transfer'),
         (N'inventory_update')
     ) AS expected(category)
LEFT JOIN
(
    SELECT category,
           SUM(executions) AS executions
    FROM
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
        WHERE rsi.start_time >= DATEADD(HOUR, -1, SYSUTCDATETIME())
        GROUP BY CASE
                   WHEN qt.query_sql_text LIKE '%leaderboard%'      THEN 'ranking_query'
                   WHEN qt.query_sql_text LIKE '%currency_ledger%'  THEN 'currency_transfer'
                   WHEN qt.query_sql_text LIKE '%inventory%'        THEN 'inventory_update'
                   ELSE 'other'
                 END
    ) AS categorized
    WHERE category IN ('ranking_query', 'currency_transfer', 'inventory_update')
    GROUP BY category
) AS observed ON observed.category = expected.category;

SELECT category,
       executions
FROM @category_counts
ORDER BY executions DESC;

IF COALESCE((SELECT SUM(executions) FROM @category_counts), 0) = 0
    PRINT 'No game workload executions found yet. Run workload\game-driver longer, or wait for Query Store flush/interval aggregation before checking again.';
GO

PRINT '03_query_store.sql: Query Store enabled and demo options ensured.';
GO
