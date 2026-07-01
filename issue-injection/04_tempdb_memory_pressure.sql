/* ==========================================================================
   Issue #4 — tempdb / memory pressure (large sort + hash spill)
   --------------------------------------------------------------------------
   Effect : A self-join on the low-cardinality `mode` column explodes the row
            count, and ORDER BY NEWID() forces a full sort that spills to
            tempdb and requests a large memory grant. Run repeatedly (e.g.
            ostress -n8) to sustain pressure during the demo.
   Demo   : runtime resource-pressure diagnosis (tempdb/memory).
   WARNING: Heavy. Run only on the isolated demo MI. TOP bounds the *output*,
            but the sort processes the full exploded set.
   Rollback: 04_tempdb_memory_pressure.rollback.sql (verify; nothing persistent)
   ========================================================================== */
SET NOCOUNT ON;
GO

PRINT 'Issue #4: generating tempdb/memory pressure (large sort + hash spill)...';

SELECT TOP (2000000) m1.match_id, m1.player_id, m2.score, m2.played_at
FROM dbo.matches AS m1
JOIN dbo.matches AS m2 ON m1.mode = m2.mode          -- low-cardinality join -> row explosion
ORDER BY NEWID()                                     -- forces a full sort spill to tempdb
OPTION (MAXDOP 4);

PRINT 'Issue #4 finished one pass. Re-run (or ostress -n) to sustain pressure.';
GO
