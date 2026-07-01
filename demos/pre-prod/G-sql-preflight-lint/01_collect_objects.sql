/* ==========================================================================
   G — Collect: gather objects & plan evidence for the pre-flight linter
   --------------------------------------------------------------------------
   Purpose : Read-only extraction that feeds the SLM linter (03_run_slm_lint.md):
             module source + plan-level anti-pattern signals + missing indexes.
   Safety  : Read-only. Suitable for MCP read-only execution.
   Usage   : Export the result sets and hand them to the local SLM prompt, or
             review inline. Filter to the batch you are about to deploy.
   ========================================================================== */
SET NOCOUNT ON;
GO

PRINT '1) Module source to lint (procedures/functions/views). Filter as needed.';
SELECT o.type_desc,
       SCHEMA_NAME(o.schema_id) + N'.' + o.name AS object_name,
       m.definition
FROM sys.sql_modules AS m
JOIN sys.objects AS o ON o.object_id = m.object_id
WHERE o.is_ms_shipped = 0
  AND (o.name LIKE N'usp_preflight%'      -- demo target; widen for a real batch
       OR o.name LIKE N'usp_%')
ORDER BY object_name;
GO

PRINT '2) Plan-level implicit conversions (CONVERT_IMPLICIT) from cached plans.';
SELECT TOP (50)
       DB_NAME() AS database_name,
       SUBSTRING(st.text, 1, 200) AS sql_preview,
       ce.query('.') AS convert_issue
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
CROSS APPLY qp.query_plan.nodes('
    declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/showplan";
    //Warnings/PlanAffectingConvert[@ConvertIssue="Seek Plan"]') AS T(ce)
WHERE qp.query_plan IS NOT NULL;
GO

PRINT '3) Plans containing table/clustered index SCANs (potential full scans).';
SELECT TOP (50)
       SUBSTRING(st.text, 1, 200) AS sql_preview,
       cp.usecounts
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE CAST(qp.query_plan AS nvarchar(max)) LIKE '%Scan="1"%'
   OR CAST(qp.query_plan AS nvarchar(max)) LIKE '%PhysicalOp="Clustered Index Scan"%'
   OR CAST(qp.query_plan AS nvarchar(max)) LIKE '%PhysicalOp="Table Scan"%'
ORDER BY cp.usecounts DESC;
GO

PRINT '4) Missing-index DMV hints (indexes the optimizer wishes existed).';
SELECT TOP (20)
       migs.avg_user_impact,
       mid.statement AS table_name,
       mid.equality_columns,
       mid.inequality_columns,
       mid.included_columns
FROM sys.dm_db_missing_index_group_stats AS migs
JOIN sys.dm_db_missing_index_groups AS mig ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY migs.avg_user_impact DESC;
GO
