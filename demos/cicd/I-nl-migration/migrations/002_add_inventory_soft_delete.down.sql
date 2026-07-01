/* ==========================================================================
   Demo I — Migration 002 DOWN: inventory 소프트 삭제 롤백
   --------------------------------------------------------------------------
   Reverses 002_add_inventory_soft_delete.up.sql. IDEMPOTENT.
   순서: 인덱스 → 컬럼(+DEFAULT 제약).
   ⚠ 롤백 시 is_deleted/deleted_at 에 담긴 소프트삭제 이력은 소실됨(문서화).
   ========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* 1) 필터드 인덱스 제거 */
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_inventory_active'
             AND object_id = OBJECT_ID(N'dbo.inventory'))
BEGIN
    DROP INDEX IX_inventory_active ON dbo.inventory;
    PRINT '002 down: IX_inventory_active dropped.';
END
GO

/* 2) deleted_at 제거 */
IF COL_LENGTH(N'dbo.inventory', N'deleted_at') IS NOT NULL
BEGIN
    ALTER TABLE dbo.inventory DROP COLUMN deleted_at;
    PRINT '002 down: inventory.deleted_at dropped.';
END
GO

/* 3) is_deleted 제거 (DEFAULT 제약 먼저 제거) */
IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_inventory_is_deleted')
BEGIN
    ALTER TABLE dbo.inventory DROP CONSTRAINT DF_inventory_is_deleted;
    PRINT '002 down: DF_inventory_is_deleted dropped.';
END
GO
IF COL_LENGTH(N'dbo.inventory', N'is_deleted') IS NOT NULL
BEGIN
    ALTER TABLE dbo.inventory DROP COLUMN is_deleted;
    PRINT '002 down: inventory.is_deleted dropped.';
END
GO

PRINT '002 down: complete.';
GO
