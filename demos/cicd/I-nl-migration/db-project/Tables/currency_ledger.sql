-- currency_ledger (동시성 경합 지점).
CREATE TABLE dbo.currency_ledger
(
    player_id      BIGINT        NOT NULL,
    currency_type  TINYINT       NOT NULL,
    balance        BIGINT        NOT NULL CONSTRAINT DF_ledger_balance DEFAULT (0),
    updated_at     DATETIME2(3)  NOT NULL CONSTRAINT DF_ledger_updated DEFAULT (SYSUTCDATETIME()),
    row_ver        ROWVERSION,
    CONSTRAINT PK_currency_ledger PRIMARY KEY CLUSTERED (player_id, currency_type),
    CONSTRAINT CK_ledger_balance CHECK (balance >= 0),
    CONSTRAINT FK_ledger_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id)
);
GO
