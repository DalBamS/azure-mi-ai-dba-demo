/* ==========================================================================
   Demo J — 보안 게이트: 과잉 권한(안티패턴) vs 최소권한(제안)
   --------------------------------------------------------------------------
   위쪽 "❌ 나쁜 예"는 PR 리뷰 에이전트가 잡아야 하는 과잉 GRANT.
   아래쪽 "✅ 제안"은 에이전트가 대체안으로 제시하는 최소권한 버전.
   실행 목적 아님(리뷰 입력/교육용).
   ========================================================================== */

/* ---------------------- ❌ 나쁜 예 (과잉 권한) ---------------------- */

-- [위험] 앱 서비스 계정에 DB 전체 제어권. 사고 시 폭발 반경 최대.
GRANT CONTROL ON DATABASE::gamedb TO [app_service];
GO
-- [위험] db_owner 역할 부여 = 사실상 관리자.
ALTER ROLE db_owner ADD MEMBER [app_service];
GO
-- [위험] public 에 광범위 권한 → 모든 사용자에게 노출.
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO public;
GO
-- [위험] 리포팅 계정에 쓰기 권한까지(읽기만 필요).
GRANT INSERT, UPDATE, DELETE ON dbo.currency_ledger TO [reporting_ro];
GO


/* ---------------------- ✅ 최소권한 제안 (에이전트 대체안) ---------------------- */

-- 앱 계정: 실제로 접근하는 객체에만, 필요한 동작만.
GRANT SELECT, INSERT, UPDATE ON dbo.inventory       TO [app_service];
GRANT SELECT, INSERT, UPDATE ON dbo.currency_ledger TO [app_service];
GRANT SELECT                 ON dbo.leaderboard     TO [app_service];
-- DELETE 는 소프트삭제(is_deleted) 사용으로 불필요 → 부여하지 않음.
GO

-- 리포팅 계정: 읽기 전용 역할로 한정.
IF DATABASE_PRINCIPAL_ID('role_reporting_ro') IS NULL
    CREATE ROLE role_reporting_ro;
GO
GRANT SELECT ON dbo.leaderboard     TO role_reporting_ro;
GRANT SELECT ON dbo.matches         TO role_reporting_ro;
ALTER ROLE role_reporting_ro ADD MEMBER [reporting_ro];
GO

/* 에이전트 코멘트 요약:
   - CONTROL/db_owner/public GRANT 3건 → 🔴 최소권한 위반.
   - 대상 객체·동작을 특정하고, 읽기전용은 전용 역할로 격리하도록 제안.
   - 권한은 개별 계정이 아닌 "역할"에 부여해 감사·회수를 단순화. */
