/* C — Diagnose plan regression: proc stats, cached plans, SET options.
   Read-only.
*/
SET NOCOUNT ON;
GO

PRINT '1) Procedure execution stats.';
SELECT DB_NAME(database_id) AS database_name,
       OBJECT_NAME(object_id, database_id) AS proc_name,
       execution_count,
       total_logical_reads / NULLIF(execution_count, 0) AS avg_logical_reads,
       total_elapsed_time / NULLIF(execution_count, 0) / 1000 AS avg_elapsed_ms,
       cached_time,
       last_execution_time
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID()
  AND object_id = OBJECT_ID(N'dbo.usp_matches_summary');
GO

PRINT '2) Cached plans and SET options.';
SELECT cp.usecounts,
       cp.cacheobjtype,
       cp.objtype,
       pa.value AS set_options,
       qp.query_plan
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_plan_attributes(cp.plan_handle) pa
WHERE pa.attribute = N'set_options'
  AND qp.dbid = DB_ID()
  AND qp.objectid = OBJECT_ID(N'dbo.usp_matches_summary');
GO

PRINT '3) Current session SET option key (compare SSMS vs app/OLE DB path).';
SELECT @@OPTIONS AS current_set_options_bitmask;
GO
