/* ==========================================================================
   Issue #4 — ROLLBACK / verification
   --------------------------------------------------------------------------
   The pressure query is transient (read-only, no schema/data change). Once it
   stops, tempdb space is reclaimed by SQL Server automatically. This script
   just reports current tempdb usage so you can confirm recovery.
   ========================================================================== */
SET NOCOUNT ON;
GO

SELECT
    SUM(user_object_reserved_page_count)     * 8 / 1024 AS user_obj_mb,
    SUM(internal_object_reserved_page_count) * 8 / 1024 AS internal_obj_mb,
    SUM(version_store_reserved_page_count)   * 8 / 1024 AS version_store_mb
FROM tempdb.sys.dm_db_file_space_usage;

PRINT 'Issue #4 rollback: transient query; no persistent state to revert.';
GO
