/* ==========================================================================
   O — 2) 정책 초안 자동생성 (미적용 / 승인 대상)
   --------------------------------------------------------------------------
   분류된 컬럼(sys.sensitivity_classifications)을 근거로
   DDM(Dynamic Data Masking) 및 RLS(Row-Level Security) T-SQL 초안을 "텍스트로 출력".
   여기서는 아무 것도 적용하지 않는다 — AI가 제안, 사람이 승인(03에서 적용).
   ========================================================================== */
SET NOCOUNT ON;
GO

/* --------------------------------------------------------------------------
   1) DDM 초안: 분류된 컬럼별 마스킹 함수 매핑 규칙
      - email  → email()
      - name/holder → partial(1,'***',0)
      - financial(card_last4) → partial(0,'****',0)  (전부 가림)
      - 기타 → default()
   생성된 스크립트를 검토 후 03_apply_masking_rls.sql 로 반영.
   -------------------------------------------------------------------------- */
SELECT
    CONCAT(
        'ALTER TABLE ', QUOTENAME(sch.name), '.', QUOTENAME(t.name),
        ' ALTER COLUMN ', QUOTENAME(c.name),
        ' ADD MASKED WITH (FUNCTION = ''',
        CASE
            WHEN c.name LIKE '%email%' OR c.name LIKE '%mail%'   THEN 'email()'
            WHEN c.name LIKE '%last4%' OR cl.information_type = 'Financial'
                                                                THEN 'partial(0,"****",0)'
            WHEN cl.information_type IN ('Name') OR c.name LIKE '%user%'
              OR c.name LIKE '%holder%' OR c.name LIKE '%nick%'  THEN 'partial(1,"***",0)'
            ELSE 'default()'
        END,
        ''');'
    ) AS ddm_draft_tsql
FROM sys.sensitivity_classifications AS cl
JOIN sys.columns  AS c   ON c.object_id = cl.major_id AND c.column_id = cl.minor_id
JOIN sys.tables   AS t   ON t.object_id = c.object_id
JOIN sys.schemas  AS sch ON sch.schema_id = t.schema_id
WHERE cl.label LIKE 'Confidential%'
ORDER BY t.name, c.name;
GO

/* --------------------------------------------------------------------------
   2) RLS 초안(정적 템플릿): region 기반 행 필터.
      안전설계 — SESSION_CONTEXT('region')가 없으면(서비스/관리 세션) 전체 허용,
      설정된 경우에만 해당 region 행으로 제한. 부하드라이버/타 데모 무영향.
      아래는 "제안 스크립트"이며 03에서 실제 생성.
   -------------------------------------------------------------------------- */
PRINT '--- RLS 제안 초안 (03_apply_masking_rls.sql 에서 적용) ---';
PRINT 'CREATE SCHEMA Security;';
PRINT 'GO';
PRINT 'CREATE FUNCTION Security.fn_players_region_predicate(@region VARCHAR(16))';
PRINT '    RETURNS TABLE WITH SCHEMABINDING AS';
PRINT '    RETURN SELECT 1 AS ok';
PRINT '           WHERE SESSION_CONTEXT(N''region'') IS NULL';
PRINT '              OR @region = CONVERT(VARCHAR(16), SESSION_CONTEXT(N''region''));';
PRINT 'GO';
PRINT 'CREATE SECURITY POLICY Security.rls_players';
PRINT '    ADD FILTER PREDICATE Security.fn_players_region_predicate(region) ON dbo.players';
PRINT '    WITH (STATE = ON);';
GO

PRINT 'O recommend: DDM/RLS 초안 생성 완료(미적용). 검토 후 03_apply_masking_rls.sql 실행.';
GO
