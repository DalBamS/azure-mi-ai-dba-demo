/* ==========================================================================
   Issue #5 — ROLLBACK: find and KILL the runaway query
   --------------------------------------------------------------------------
   Run this in a SEPARATE session to locate the runaway request and stop it.
   No persistent state is changed (read-only query); killing it is the fix.
   ========================================================================== */
SET NOCOUNT ON;
GO

-- Find the long-running runaway request(s).
SELECT r.session_id,
       r.status,
       r.cpu_time,
       r.total_elapsed_time / 1000 AS elapsed_sec,
       r.wait_type,
       SUBSTRING(t.text, 1, 120) AS query_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID
  AND t.text LIKE '%CROSS JOIN dbo.matches%';

-- Then stop it (replace <spid> with the session_id above):
--   KILL <spid>;

PRINT 'Issue #5 rollback: identify the SPID above and run KILL <spid>.';
GO
