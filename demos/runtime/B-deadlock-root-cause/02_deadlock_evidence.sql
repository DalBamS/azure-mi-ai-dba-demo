/* B — Deadlock evidence from system_health Extended Events.
   Read-only. Pulls recent xml_deadlock_report entries.
*/
SET NOCOUNT ON;
GO

;WITH target_data AS
(
    SELECT CAST(xet.target_data AS XML) AS target_xml
    FROM sys.dm_xe_session_targets xet
    JOIN sys.dm_xe_sessions xe ON xe.address = xet.event_session_address
    WHERE xe.name = N'system_health'
      AND xet.target_name = N'ring_buffer'
),
deadlocks AS
(
    SELECT xed.value(N'(@timestamp)[1]', N'datetime2') AS utc_time,
           xed.query(N'(data/value/deadlock)[1]') AS deadlock_xml
    FROM target_data
    CROSS APPLY target_xml.nodes(N'RingBufferTarget/event[@name="xml_deadlock_report"]') AS tab(xed)
)
SELECT TOP (10) utc_time, deadlock_xml
FROM deadlocks
ORDER BY utc_time DESC;
GO
