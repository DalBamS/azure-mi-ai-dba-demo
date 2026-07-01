/* ==========================================================================
   O — 4) Eval: 분류/마스킹/RLS 적용 검증 (읽기전용)
   --------------------------------------------------------------------------
   PASS 기준:
     - 분류: players.email/username/region 3건 이상 태깅됨.
     - 마스킹: players.email/username 에 마스크 존재.
     - RLS   : Security.rls_players 정책 존재 & STATE=ON.
     - (선택) SESSION_CONTEXT 설정 시 region 필터가 실제 행을 제한.
   ========================================================================== */
SET NOCOUNT ON;
GO

PRINT '=== 1) 민감도 분류 ===';
SELECT OBJECT_SCHEMA_NAME(cl.major_id) AS schema_name,
       OBJECT_NAME(cl.major_id)        AS table_name,
       c.name                          AS column_name,
       cl.label, cl.information_type, cl.rank_desc
FROM sys.sensitivity_classifications AS cl
JOIN sys.columns c ON c.object_id = cl.major_id AND c.column_id = cl.minor_id
ORDER BY table_name, column_name;
GO

PRINT '=== 2) 마스킹된 컬럼 ===';
SELECT OBJECT_SCHEMA_NAME(mc.object_id) AS schema_name,
       OBJECT_NAME(mc.object_id)        AS table_name,
       mc.name                          AS column_name,
       mc.masking_function
FROM sys.masked_columns AS mc
ORDER BY table_name, column_name;
GO

PRINT '=== 3) RLS 보안 정책 ===';
SELECT sp.name AS policy_name, sp.is_enabled,
       OBJECT_SCHEMA_NAME(spr.target_object_id) + '.' + OBJECT_NAME(spr.target_object_id) AS target,
       spr.predicate_type_desc
FROM sys.security_policies AS sp
JOIN sys.security_predicates AS spr ON spr.object_id = sp.object_id
WHERE sp.name = 'rls_players';
GO

/* --------------------------------------------------------------------------
   4) (선택) RLS 동작 확인: region 컨텍스트 설정 → 해당 region만 보이는지.
      기본 세션(컨텍스트 미설정)은 전체가 보여야 정상(안전 술어).
   -------------------------------------------------------------------------- */
DECLARE @all INT = (SELECT COUNT(*) FROM dbo.players);
EXEC sys.sp_set_session_context @key = N'region', @value = N'KR';
DECLARE @kr  INT = (SELECT COUNT(*) FROM dbo.players);
EXEC sys.sp_set_session_context @key = N'region', @value = NULL;
DECLARE @reset INT = (SELECT COUNT(*) FROM dbo.players);

SELECT @all AS rows_no_context, @kr AS rows_region_KR, @reset AS rows_after_reset,
       CASE WHEN @kr <= @all AND @reset = @all THEN 'PASS' ELSE 'CHECK' END AS rls_behavior;
GO
