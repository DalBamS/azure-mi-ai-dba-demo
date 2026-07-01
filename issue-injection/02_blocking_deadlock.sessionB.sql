/* ==========================================================================
   Issue #2 — Blocking / Deadlock (SESSION B)
   --------------------------------------------------------------------------
   Run alongside 02_blocking_deadlock.sessionA.sql (two windows, same time).
   This session locks INVENTORY first, then CURRENCY — the opposite order of
   session A — which forces a deadlock (error 1205).
   ========================================================================== */
SET NOCOUNT ON;
GO

DECLARE @i INT = 0;
WHILE @i < 50
BEGIN
    BEGIN TRY
        BEGIN TRAN;
            -- B locks INVENTORY first ...
            UPDATE dbo.inventory
                SET quantity = quantity + 1, updated_at = SYSUTCDATETIME()
            WHERE player_id = 2 AND item_id = 1;

            WAITFOR DELAY '00:00:00.100';

            -- ... then CURRENCY (opposite of session A)
            UPDATE dbo.currency_ledger
                SET balance = balance + 1, updated_at = SYSUTCDATETIME()
            WHERE player_id = 1 AND currency_type = 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF ERROR_NUMBER() = 1205
            PRINT CONCAT('SESSION B: deadlock victim on iteration ', @i, ' (expected).');
        ELSE
            PRINT CONCAT('SESSION B: error ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE());
    END CATCH;
    SET @i += 1;
END
PRINT 'SESSION B finished.';
GO
