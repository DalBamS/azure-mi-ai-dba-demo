/* ==========================================================================
   Demo J — 위험 샘플 마이그레이션 #1 (일부러 위험하게 작성한 PR)
   --------------------------------------------------------------------------
   이 파일은 "나쁜 예"입니다. 실행 목적이 아니라, PR 리뷰 에이전트(AI 하네스)가
   어떤 위험을 잡아내는지 보여주기 위한 입력입니다. (ai-review/ 의 리포트와 짝)
   inventory 는 핫·대형 테이블임을 상기하세요.
   ========================================================================== */
SET NOCOUNT ON;
GO

/* [위험 1] 대형 테이블에 NOT NULL 컬럼을 상수 아닌 DEFAULT 없이 추가 후 즉시 백필.
   - NOT NULL + 비상수 DEFAULT 조합/후속 UPDATE 는 전체 테이블 스캔·대량 락 유발.
   - 온라인 옵션 없음 → 장시간 스키마 잠금(Sch-M) 으로 워크로드 차단 위험. */
ALTER TABLE dbo.inventory ADD last_seen_at DATETIME2(3) NOT NULL
    CONSTRAINT DF_inventory_last_seen DEFAULT (SYSUTCDATETIME());
GO
UPDATE dbo.inventory SET last_seen_at = updated_at;   -- 전체 행 갱신(대량 락/로그)
GO

/* [위험 2] 대형 테이블에 OFFLINE 인덱스 생성 (ONLINE=ON 누락).
   - 인덱스 빌드 동안 테이블이 잠겨 재화/인벤 트랜잭션이 대기. */
CREATE NONCLUSTERED INDEX IX_inventory_last_seen
    ON dbo.inventory (last_seen_at);   -- WITH (ONLINE = ON) 없음
GO

/* [위험 3] Breaking change: 애플리케이션이 참조하는 컬럼 rename.
   - 배포 순간 구버전 앱 쿼리가 즉시 깨짐(무중단 배포 불가). */
EXEC sp_rename 'dbo.inventory.quantity', 'qty', 'COLUMN';
GO

/* [위험 4] 롤백 스크립트 없음 — 되돌릴 방법이 PR 에 포함되지 않음. */
