/* B — Safe pattern: consistent lock ordering for the currency-transfer hot path.
   This is a reference remediation pattern, not automatically installed.
   Human approval required before adapting into app/stored-proc code.
*/
CREATE OR ALTER PROCEDURE dbo.usp_transfer_gold_safe_example
    @from_player_id BIGINT,
    @to_player_id   BIGINT,
    @amount         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @from_player_id = @to_player_id
        THROW 50001, 'from_player_id and to_player_id must differ.', 1;
    IF @amount <= 0
        THROW 50002, 'amount must be positive.', 1;

    DECLARE @first BIGINT = IIF(@from_player_id < @to_player_id, @from_player_id, @to_player_id);
    DECLARE @second BIGINT = IIF(@from_player_id < @to_player_id, @to_player_id, @from_player_id);

    BEGIN TRAN;
        -- Acquire locks in a deterministic order for every code path.
        -- Two point-lookups are used instead of `IN (...) ORDER BY` so lock
        -- acquisition order is explicit and not left to optimizer choices.
        SELECT player_id
        FROM dbo.currency_ledger WITH (UPDLOCK, HOLDLOCK, INDEX(PK_currency_ledger))
        WHERE currency_type = 1 AND player_id = @first;

        SELECT player_id
        FROM dbo.currency_ledger WITH (UPDLOCK, HOLDLOCK, INDEX(PK_currency_ledger))
        WHERE currency_type = 1 AND player_id = @second;

        UPDATE dbo.currency_ledger
            SET balance = balance - @amount, updated_at = SYSUTCDATETIME()
        WHERE player_id = @from_player_id
          AND currency_type = 1
          AND balance >= @amount;

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK;
            THROW 50003, 'insufficient balance or missing source row.', 1;
        END;

        UPDATE dbo.currency_ledger
            SET balance = balance + @amount, updated_at = SYSUTCDATETIME()
        WHERE player_id = @to_player_id
          AND currency_type = 1;
    COMMIT;
END
GO

PRINT 'Reference safe pattern created: dbo.usp_transfer_gold_safe_example.';
GO
