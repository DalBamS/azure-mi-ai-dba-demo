/* ==========================================================================
   O — 5) Rollback/cleanup: 모든 정책·마스크·분류·데모 객체 원복
   --------------------------------------------------------------------------
   순서: 보안정책 → 술어함수 → Security 스키마 → DDM 마스크 → 분류 → 선택 테이블.
   ========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* 1) RLS 정책 & 함수 & 스키마 */
IF OBJECT_ID(N'Security.rls_players', N'SP') IS NOT NULL
    DROP SECURITY POLICY Security.rls_players;
GO
IF OBJECT_ID(N'Security.fn_players_region_predicate', N'IF') IS NOT NULL
    DROP FUNCTION Security.fn_players_region_predicate;
GO
IF SCHEMA_ID(N'Security') IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM sys.objects WHERE schema_id = SCHEMA_ID(N'Security'))
    EXEC(N'DROP SCHEMA Security;');
GO

/* 2) DDM 마스크 제거 (players) */
IF EXISTS (SELECT 1 FROM sys.masked_columns mc JOIN sys.columns c
           ON c.object_id = mc.object_id AND c.column_id = mc.column_id
           WHERE mc.object_id = OBJECT_ID(N'dbo.players') AND c.name = 'email')
    ALTER TABLE dbo.players ALTER COLUMN email DROP MASKED;
IF EXISTS (SELECT 1 FROM sys.masked_columns mc JOIN sys.columns c
           ON c.object_id = mc.object_id AND c.column_id = mc.column_id
           WHERE mc.object_id = OBJECT_ID(N'dbo.players') AND c.name = 'username')
    ALTER TABLE dbo.players ALTER COLUMN username DROP MASKED;
GO

/* 3) 민감도 분류 제거 (players) */
IF EXISTS (SELECT 1 FROM sys.sensitivity_classifications WHERE major_id = OBJECT_ID(N'dbo.players')
           AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.players'), 'email', 'ColumnId'))
    DROP SENSITIVITY CLASSIFICATION FROM dbo.players.email;
IF EXISTS (SELECT 1 FROM sys.sensitivity_classifications WHERE major_id = OBJECT_ID(N'dbo.players')
           AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.players'), 'username', 'ColumnId'))
    DROP SENSITIVITY CLASSIFICATION FROM dbo.players.username;
IF EXISTS (SELECT 1 FROM sys.sensitivity_classifications WHERE major_id = OBJECT_ID(N'dbo.players')
           AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.players'), 'region', 'ColumnId'))
    DROP SENSITIVITY CLASSIFICATION FROM dbo.players.region;
GO

/* 4) 선택 payment_methods (마스크/분류/테이블) 정리 */
IF OBJECT_ID(N'dbo.payment_methods', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.sensitivity_classifications WHERE major_id = OBJECT_ID(N'dbo.payment_methods'))
    BEGIN
        EXEC(N'DROP SENSITIVITY CLASSIFICATION FROM dbo.payment_methods.card_holder;');
        EXEC(N'DROP SENSITIVITY CLASSIFICATION FROM dbo.payment_methods.card_last4;');
        EXEC(N'DROP SENSITIVITY CLASSIFICATION FROM dbo.payment_methods.billing_email;');
    END
    DROP TABLE dbo.payment_methods;   -- 데모 테이블 제거(마스크도 함께 사라짐)
    PRINT 'O rollback: dropped dbo.payment_methods.';
END
GO

PRINT 'O rollback: classifications/masks/RLS reverted.';
GO
