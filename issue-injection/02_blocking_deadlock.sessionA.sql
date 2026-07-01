/* ==========================================================================
   Issue #2 — Blocking / Deadlock (SESSION A)
   --------------------------------------------------------------------------
   Run this in one query window, and 02_blocking_deadlock.sessionB.sql in
   another, AT THE SAME TIME. They update currency_ledger and inventory in
   OPPOSITE order, producing a deadlock (error 1205) — the reverse of the
   normal driver's safe ascending lock order.
   Demo   : B (deadlock root-cause analysis).
   Rollback: 02_blocking_deadlock.rollback.sql
   Contention keys: player_id = 1 (currency gold) and player_id = 2 (inventory item 1)
   ========================================================================== */
SET NOCOUNT ON;
GO

DECLARE @i INT = 0;
WHILE @i < 50
BEGIN
    BEGIN TRY
        BEGIN TRAN;
            -- A locks CURRENCY first ...
            UPDATE dbo.currency_ledger
                SET balance = balance + 1, updated_at = SYSUTCDATETIME()
            WHERE player_id = 1 AND currency_type = 1;

            WAITFOR DELAY '00:00:00.100';

            -- ... then INVENTORY (opposite of session B)
            UPDATE dbo.inventory
                SET quantity = quantity + 1, updated_at = SYSUTCDATETIME()
            WHERE player_id = 2 AND item_id = 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF ERROR_NUMBER() = 1205
            PRINT CONCAT('SESSION A: deadlock victim on iteration ', @i, ' (expected).');
        ELSE
            PRINT CONCAT('SESSION A: error ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE());
    END CATCH;
    SET @i += 1;
END
PRINT 'SESSION A finished.';
GO
