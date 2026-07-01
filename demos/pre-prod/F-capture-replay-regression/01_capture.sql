/* ==========================================================================
   F — Capture: record a representative workload window (Extended Events)
   --------------------------------------------------------------------------
   Purpose : Capture the batch/RPC activity of a baseline window so it can be
             replayed against another tier/version and compared for regression.
             This is the "capture" half of a Distributed Replay-style flow,
             but lightweight and MI-friendly.
   Safety  : Creates a SERVER-level XEvents session (state change, not data).
             Remove it afterwards with 05_cleanup.sql.
   Note    : Query Store is the primary comparison source (03_compare_waits.sql);
             this XE capture provides the statement stream for tools like
             ostress/RML if you want a faithful replay (see 02_replay.md).
   ========================================================================== */
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'demo_capture_replay')
BEGIN
    ALTER EVENT SESSION demo_capture_replay ON SERVER STATE = STOP;
    DROP EVENT SESSION demo_capture_replay ON SERVER;
END
GO

DECLARE @dbid int = DB_ID();   -- capture only the current (game) database
DECLARE @sql nvarchar(max) = N'
CREATE EVENT SESSION demo_capture_replay ON SERVER
ADD EVENT sqlserver.rpc_completed(
    ACTION (sqlserver.database_id, sqlserver.sql_text)
    WHERE (sqlserver.database_id = ' + CAST(@dbid AS nvarchar(10)) + N')),
ADD EVENT sqlserver.sql_batch_completed(
    ACTION (sqlserver.database_id, sqlserver.sql_text)
    WHERE (sqlserver.database_id = ' + CAST(@dbid AS nvarchar(10)) + N'))
ADD TARGET package0.ring_buffer (SET max_memory = 8192)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS, TRACK_CAUSALITY = ON, STARTUP_STATE = OFF);';
EXEC (@sql);
GO

ALTER EVENT SESSION demo_capture_replay ON SERVER STATE = START;
GO

PRINT 'F capture started: XEvents session [demo_capture_replay] recording rpc/batch completed for this DB.';
PRINT 'Run the baseline workload now (workload\game-driver). Then read the ring buffer, or move to replay.';
GO

/* Peek at what has been captured so far (read-only). Run after some load. */
;WITH xe AS
(
    SELECT CAST(xet.target_data AS xml) AS target_xml
    FROM sys.dm_xe_session_targets xet
    JOIN sys.dm_xe_sessions xe ON xe.address = xet.event_session_address
    WHERE xe.name = N'demo_capture_replay' AND xet.target_name = N'ring_buffer'
)
SELECT TOP (20)
       ev.value('(@timestamp)[1]', 'datetime2')                             AS utc_time,
       ev.value('(@name)[1]', 'nvarchar(64)')                               AS event_name,
       ev.value('(data[@name="duration"]/value)[1]', 'bigint') / 1000.0     AS duration_ms,
       ev.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)')     AS sql_text
FROM xe
CROSS APPLY target_xml.nodes('RingBufferTarget/event') AS t(ev)
ORDER BY utc_time DESC;
GO
