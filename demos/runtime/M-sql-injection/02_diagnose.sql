/* M — Diagnose SQL injection evidence.
   Read-only.
*/
SET NOCOUNT ON;
GO

PRINT '1) Vulnerable procedure definition.';
SELECT OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_search_players_unsafe')) AS proc_definition;
GO

PRINT '2) Recent cached statements with injection-like patterns.';
SELECT TOP (50)
       qs.execution_count,
       qs.last_execution_time,
       SUBSTRING(st.text, 1, 4000) AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE '%usp_search_players_unsafe%'
   OR st.text LIKE '%OR 1=1%'
   OR st.text LIKE '%--%'
ORDER BY qs.last_execution_time DESC;
GO

PRINT '3) Auditing/Defender connection points (configure in infra for live demos).';
SELECT name, is_state_enabled
FROM sys.database_audit_specifications;
GO
