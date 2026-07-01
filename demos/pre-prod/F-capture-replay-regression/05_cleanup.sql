/* ==========================================================================
   F — Cleanup: remove the capture XEvents session
   --------------------------------------------------------------------------
   Drops the server-level [demo_capture_replay] session created by 01_capture.sql
   so the demo leaves no leftover server objects. Query Store data is left
   intact (it is normal telemetry, not demo state).
   ========================================================================== */
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'demo_capture_replay')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name = N'demo_capture_replay')
        ALTER EVENT SESSION demo_capture_replay ON SERVER STATE = STOP;
    DROP EVENT SESSION demo_capture_replay ON SERVER;
    PRINT 'F cleanup: dropped XEvents session [demo_capture_replay].';
END
ELSE
    PRINT 'F cleanup: XEvents session [demo_capture_replay] already absent.';
GO
