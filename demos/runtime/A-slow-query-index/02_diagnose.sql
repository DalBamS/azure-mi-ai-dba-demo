/* A — Diagnose: collect evidence for the slow leaderboard query.
   Read-only. Suitable for MCP read-only execution.
*/
SET NOCOUNT ON;
GO

PRINT '1) Is the expected ranking index present?';
SELECT i.name, i.type_desc, i.is_disabled, c.name AS key_column, ic.key_ordinal, ic.is_included_column
FROM sys.indexes i
LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
LEFT JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID(N'dbo.leaderboard')
ORDER BY i.name, ic.key_ordinal, ic.index_column_id;
GO

PRINT '2) Missing-index DMV evidence for leaderboard.';
SELECT TOP (20)
       migs.user_seeks,
       migs.user_scans,
       migs.avg_total_user_cost,
       migs.avg_user_impact,
       mid.equality_columns,
       mid.inequality_columns,
       mid.included_columns,
       statement_text = mid.statement
FROM sys.dm_db_missing_index_group_stats AS migs
JOIN sys.dm_db_missing_index_groups AS mig ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
  AND mid.statement LIKE '%leaderboard%'
ORDER BY (migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans)) DESC;
GO

PRINT '3) Recent cached query stats for leaderboard ranking.';
SELECT TOP (20)
       qs.execution_count,
       qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS avg_logical_reads,
       qs.total_elapsed_time / NULLIF(qs.execution_count, 0) / 1000 AS avg_elapsed_ms,
       SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
                 CASE qs.statement_end_offset
                      WHEN -1 THEN DATALENGTH(st.text)
                      ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2 + 1
                 END) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE '%dbo.leaderboard%'
ORDER BY avg_logical_reads DESC;
GO
