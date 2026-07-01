/* B — Eval: confirm deadlock evidence exists and references expected objects.
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
    SELECT TOP (20)
           xed.value(N'(@timestamp)[1]', N'datetime2') AS utc_time,
           CONVERT(nvarchar(max), xed.query(N'(data/value/deadlock)[1]')) AS deadlock_text
    FROM target_data
    CROSS APPLY target_xml.nodes(N'RingBufferTarget/event[@name="xml_deadlock_report"]') AS tab(xed)
    ORDER BY utc_time DESC
)
SELECT TOP (1)
       utc_time,
       CASE WHEN deadlock_text LIKE '%currency_ledger%' THEN 'PASS' ELSE 'CHECK' END AS mentions_currency_ledger,
       CASE WHEN deadlock_text LIKE '%inventory%' THEN 'PASS' ELSE 'CHECK' END AS mentions_inventory
FROM deadlocks
ORDER BY utc_time DESC;
GO
