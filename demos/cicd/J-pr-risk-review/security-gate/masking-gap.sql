/* ==========================================================================
   Demo J — 보안 게이트: 민감 컬럼 마스킹(DDM) 누락 검출 + 제안
   --------------------------------------------------------------------------
   신규/변경 컬럼 중 민감정보(PII)에 Dynamic Data Masking 이 빠진 것을 에이전트가 지적.
   ========================================================================== */
SET NOCOUNT ON;
GO

/* ---------------------- ❌ 나쁜 예 (마스킹 누락) ---------------------- */
-- [위험] players.email 은 PII 인데 마스킹 없이 그대로 노출.
--        (원본 스키마에도 마스킹이 없다면 이 변경 PR 에서 함께 교정 권고)
ALTER TABLE dbo.players ADD phone NVARCHAR(32) NULL;   -- PII 추가, 마스킹 미지정
GO
ALTER TABLE dbo.players ADD birth_date DATE NULL;      -- 준식별자, 마스킹 미지정
GO


/* ---------------------- ✅ 제안 (DDM 적용) ---------------------- */
-- email: 기본 email 마스크(a****@domain 형태).
IF EXISTS (SELECT 1 FROM sys.masked_columns
           WHERE object_id = OBJECT_ID(N'dbo.players') AND name = N'email')
    PRINT 'email already masked.';
ELSE
    ALTER TABLE dbo.players ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()');
GO
-- phone: 부분 마스크(뒷 4자리만 노출).
ALTER TABLE dbo.players ALTER COLUMN phone
    ADD MASKED WITH (FUNCTION = 'partial(0, "***-****-", 4)');
GO
-- birth_date: 기본 마스크.
ALTER TABLE dbo.players ALTER COLUMN birth_date ADD MASKED WITH (FUNCTION = 'default()');
GO

/* 추가 권고(에이전트):
   - 민감 컬럼에는 Data Classification 라벨(SENSITIVITY)도 함께 부여.
   - 마스킹 해제 권한(UNMASK)은 최소 인원/역할에만(운영 계정 제외).
   - 실제 값 필요 리포팅은 뷰/역할로 분리. */
