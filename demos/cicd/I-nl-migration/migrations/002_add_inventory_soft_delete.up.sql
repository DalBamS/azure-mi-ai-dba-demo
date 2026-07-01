/* ==========================================================================
   Demo I — Migration 002 UP: inventory 소프트 삭제 컬럼 + 필터드 인덱스
   --------------------------------------------------------------------------
   Source : 자연어 요구(prompts/nl-request.md 예시 2).
   Safety : IDEMPOTENT. inventory 는 핫·대형 테이블 → 락 최소화.
            - is_deleted 는 DEFAULT 0 로 추가(SQL Server 는 NOT NULL + 상수 DEFAULT
              추가가 메타데이터 전용 연산 → 대형 테이블에서도 즉시).
   Rollback: 002_add_inventory_soft_delete.down.sql
   ========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* 1) is_deleted BIT NOT NULL DEFAULT 0 (메타데이터 전용 추가) */
IF COL_LENGTH(N'dbo.inventory', N'is_deleted') IS NULL
BEGIN
    ALTER TABLE dbo.inventory
        ADD is_deleted BIT NOT NULL
            CONSTRAINT DF_inventory_is_deleted DEFAULT (0);
    PRINT '002 up: inventory.is_deleted added.';
END
ELSE
    PRINT '002 up: inventory.is_deleted already exists (no-op).';
GO

/* 2) deleted_at DATETIME2(3) NULL */
IF COL_LENGTH(N'dbo.inventory', N'deleted_at') IS NULL
BEGIN
    ALTER TABLE dbo.inventory ADD deleted_at DATETIME2(3) NULL;
    PRINT '002 up: inventory.deleted_at added.';
END
ELSE
    PRINT '002 up: inventory.deleted_at already exists (no-op).';
GO

/* 3) 활성(미삭제) 아이템 필터드 인덱스 — 조회 경로 최적화 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_inventory_active'
                 AND object_id = OBJECT_ID(N'dbo.inventory'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX IX_inventory_active
            ON dbo.inventory (player_id)
            INCLUDE (item_id, quantity)
            WHERE is_deleted = 0
            WITH (ONLINE = ON, RESUMABLE = ON);
    END TRY
    BEGIN CATCH
        PRINT '002 up: ONLINE index failed, retrying offline. ' + ERROR_MESSAGE();
        CREATE NONCLUSTERED INDEX IX_inventory_active
            ON dbo.inventory (player_id)
            INCLUDE (item_id, quantity)
            WHERE is_deleted = 0;
    END CATCH
    PRINT '002 up: IX_inventory_active (filtered) created.';
END
ELSE
    PRINT '002 up: IX_inventory_active already exists (no-op).';
GO

PRINT '002 up: complete.';
GO
