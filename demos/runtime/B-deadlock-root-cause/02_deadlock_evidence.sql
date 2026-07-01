/* B — Deadlock evidence from system_health Extended Events.
   Read-only. Pulls recent xml_deadlock_report entries.

   Azure SQL MI/DB note: the system_health ring_buffer target frequently comes
   back EMPTY for deadlock graphs on Managed Instance, while the event_file
   (.xel) target retains them reliably. We therefore read the event_file first
   and UNION a ring_buffer fallback so this works on both MI and on-prem/IaaS
   SQL Server (where ring_buffer is typically populated).
*/
SET NOCOUNT ON;
GO

;WITH ef AS
(
    -- Primary source on Azure SQL MI/DB: the system_health event_file (.xel) target.
    SELECT CAST(event_data AS XML) AS deadlock_xml
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
),
rb_target AS
(
    SELECT CAST(xet.target_data AS XML) AS target_xml
    FROM sys.dm_xe_session_targets xet
    JOIN sys.dm_xe_sessions xe ON xe.address = xet.event_session_address
    WHERE xe.name = N'system_health'
      AND xet.target_name = N'ring_buffer'
),
rb AS
(
    -- Fallback for on-prem/IaaS SQL Server: the ring_buffer target.
    SELECT xed.query(N'.') AS deadlock_xml
    FROM rb_target
    CROSS APPLY target_xml.nodes(N'RingBufferTarget/event[@name="xml_deadlock_report"]') AS tab(xed)
),
all_deadlocks AS
(
    SELECT deadlock_xml FROM ef
    UNION ALL
    SELECT deadlock_xml FROM rb
)
SELECT TOP (10)
       deadlock_xml.value(N'(event/@timestamp)[1]', N'datetime2') AS utc_time,
       deadlock_xml AS deadlock_xml
FROM all_deadlocks
ORDER BY utc_time DESC;
GO
