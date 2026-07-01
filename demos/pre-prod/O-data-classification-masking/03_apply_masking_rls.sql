/* ==========================================================================
   O — 3) 정책 적용 (승인 후 실행)
   --------------------------------------------------------------------------
   02에서 검토·승인한 DDM/RLS 초안을 실제 반영.
   - DDM: players.email(email 마스크), players.username(부분 마스크)
          [선택] payment_methods.card_holder/card_last4/billing_email
   - RLS: region 기반 필터(안전 술어 — 컨텍스트 없으면 전체 허용)
   원복 : 05_rollback.sql
   ========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* --------------------------- DDM 적용 --------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
               JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
               WHERE mc.object_id = OBJECT_ID(N'dbo.players') AND c.name = 'email')
    ALTER TABLE dbo.players ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()');

IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
               JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
               WHERE mc.object_id = OBJECT_ID(N'dbo.players') AND c.name = 'username')
    ALTER TABLE dbo.players ALTER COLUMN username ADD MASKED WITH (FUNCTION = 'partial(1,"***",0)');
GO

IF OBJECT_ID(N'dbo.payment_methods', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
                   JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
                   WHERE mc.object_id = OBJECT_ID(N'dbo.payment_methods') AND c.name = 'card_holder')
        EXEC(N'ALTER TABLE dbo.payment_methods ALTER COLUMN card_holder ADD MASKED WITH (FUNCTION = ''partial(1,"***",0)'');');

    IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
                   JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
                   WHERE mc.object_id = OBJECT_ID(N'dbo.payment_methods') AND c.name = 'card_last4')
        EXEC(N'ALTER TABLE dbo.payment_methods ALTER COLUMN card_last4 ADD MASKED WITH (FUNCTION = ''partial(0,"****",0)'');');

    IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
                   JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
                   WHERE mc.object_id = OBJECT_ID(N'dbo.payment_methods') AND c.name = 'billing_email')
        EXEC(N'ALTER TABLE dbo.payment_methods ALTER COLUMN billing_email ADD MASKED WITH (FUNCTION = ''email()'');');
    PRINT 'O apply: payment_methods DDM applied.';
END
GO

/* --------------------------- RLS 적용 --------------------------- */
IF SCHEMA_ID(N'Security') IS NULL
    EXEC(N'CREATE SCHEMA Security;');
GO

/* 재실행 안전: 함수가 정책에 schema-bound이므로 SECURITY POLICY 를 먼저 DROP 후 함수 DROP */
IF OBJECT_ID(N'Security.rls_players', N'SP') IS NOT NULL   -- security policy
    DROP SECURITY POLICY Security.rls_players;
GO
IF OBJECT_ID(N'Security.fn_players_region_predicate', N'IF') IS NOT NULL
    DROP FUNCTION Security.fn_players_region_predicate;
GO
/* 데모용 술어: region 필터가 실제로 관찰되도록 관리자 예외를 두지 않는다.
   (SESSION_CONTEXT('region') 미설정 시에는 전체 허용 → 부하 드라이버/타 데모 무영향) */
CREATE FUNCTION Security.fn_players_region_predicate(@region VARCHAR(16))
    RETURNS TABLE WITH SCHEMABINDING AS
    RETURN SELECT 1 AS ok
           WHERE SESSION_CONTEXT(N'region') IS NULL                          -- 서비스/관리 세션 = 전체 허용(안전)
              OR @region = CONVERT(VARCHAR(16), SESSION_CONTEXT(N'region'));  -- region 컨텍스트 일치 행만
GO

CREATE SECURITY POLICY Security.rls_players
    ADD FILTER PREDICATE Security.fn_players_region_predicate(region) ON dbo.players
    WITH (STATE = ON);
GO

PRINT 'O apply: DDM + RLS 적용 완료. 04_eval.sql 로 검증.';
GO
