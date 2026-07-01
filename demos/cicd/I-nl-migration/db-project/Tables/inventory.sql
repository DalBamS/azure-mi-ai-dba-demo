-- inventory (핫·대형 테이블). 데모 I 마이그레이션 002(소프트 삭제) 반영.
CREATE TABLE dbo.inventory
(
    player_id    BIGINT        NOT NULL,
    item_id      INT           NOT NULL,
    quantity     INT           NOT NULL CONSTRAINT DF_inventory_qty DEFAULT (0),
    acquired_at  DATETIME2(3)  NOT NULL CONSTRAINT DF_inventory_acquired DEFAULT (SYSUTCDATETIME()),
    updated_at   DATETIME2(3)  NOT NULL CONSTRAINT DF_inventory_updated DEFAULT (SYSUTCDATETIME()),
    is_deleted   BIT           NOT NULL CONSTRAINT DF_inventory_is_deleted DEFAULT (0),
    deleted_at   DATETIME2(3)  NULL,
    row_ver      ROWVERSION,
    CONSTRAINT PK_inventory PRIMARY KEY CLUSTERED (player_id, item_id),
    CONSTRAINT CK_inventory_qty CHECK (quantity >= 0),
    CONSTRAINT FK_inventory_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id)
);
GO

CREATE NONCLUSTERED INDEX IX_inventory_item
    ON dbo.inventory (item_id) INCLUDE (quantity);
GO

CREATE NONCLUSTERED INDEX IX_inventory_active
    ON dbo.inventory (player_id) INCLUDE (item_id, quantity)
    WHERE is_deleted = 0;
GO
