/* B — Eval: confirm deadlock evidence exists and references expected objects.
   Reads the system_health event_file (.xel) target first (reliable on Azure
   SQL MI/DB), with a ring_buffer fallback for on-prem/IaaS SQL Server.
*/
SET NOCOUNT ON;
GO

;WITH ef AS
(
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
    SELECT xed.query(N'.') AS deadlock_xml
    FROM rb_target
    CROSS APPLY target_xml.nodes(N'RingBufferTarget/event[@name="xml_deadlock_report"]') AS tab(xed)
),
deadlocks AS
(
    SELECT TOP (20)
           deadlock_xml.value(N'(event/@timestamp)[1]', N'datetime2') AS utc_time,
           CONVERT(nvarchar(max), deadlock_xml) AS deadlock_text
    FROM (SELECT deadlock_xml FROM ef UNION ALL SELECT deadlock_xml FROM rb) x
    ORDER BY utc_time DESC
)
SELECT TOP (1)
       utc_time,
       CASE WHEN deadlock_text LIKE '%currency_ledger%' THEN 'PASS' ELSE 'CHECK' END AS mentions_currency_ledger,
       CASE WHEN deadlock_text LIKE '%inventory%' THEN 'PASS' ELSE 'CHECK' END AS mentions_inventory
FROM deadlocks
ORDER BY utc_time DESC;
GO
