/* B — Observe current blocking/waits/locks.
   Read-only. Run while issue-injection #2 sessions are active.
*/
SET NOCOUNT ON;
GO

SELECT r.session_id,
       r.blocking_session_id,
       r.status,
       r.wait_type,
       r.wait_time,
       r.wait_resource,
       r.command,
       DB_NAME(r.database_id) AS database_name,
       SUBSTRING(t.text, 1, 4000) AS sql_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID
  AND (r.blocking_session_id <> 0 OR t.text LIKE '%currency_ledger%' OR t.text LIKE '%inventory%')
ORDER BY r.blocking_session_id DESC, r.session_id;
GO

SELECT tl.request_session_id,
       tl.resource_type,
       tl.resource_associated_entity_id,
       OBJECT_NAME(p.object_id) AS object_name,
       tl.request_mode,
       tl.request_status
FROM sys.dm_tran_locks tl
LEFT JOIN sys.partitions p ON p.hobt_id = tl.resource_associated_entity_id
WHERE tl.resource_database_id = DB_ID()
  AND OBJECT_NAME(p.object_id) IN (N'currency_ledger', N'inventory')
ORDER BY tl.request_session_id, object_name, tl.request_mode;
GO
