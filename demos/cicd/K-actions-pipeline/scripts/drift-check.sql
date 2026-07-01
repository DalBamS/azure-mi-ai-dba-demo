/* ==========================================================================
   Demo K — 스키마 drift / 회귀 가드 (배포된 임시 DB 대상)
   --------------------------------------------------------------------------
   목적 : DACPAC 배포 후, 핵심 스키마 계약(테이블/컬럼/인덱스)이 실제로 존재하는지
          읽기전용으로 검증. 하나라도 어긋나면 RAISERROR 로 CI 실패 유도.
   실행 : sqlcmd -b (오류 시 비정상 종료). 읽기만 하므로 안전.
   가드 : 실제 배포가 없으면 이 스크립트는 CI 에서 스킵됨(db-ci.yml 참고).
   ========================================================================== */
SET NOCOUNT ON;
GO

DECLARE @drift INT = 0;

/* 1) 필수 테이블 존재 */
;WITH req(name) AS (
    SELECT v.name FROM (VALUES
        (N'dbo.players'), (N'dbo.inventory'), (N'dbo.currency_ledger'),
        (N'dbo.matches'), (N'dbo.leaderboard'), (N'dbo.seasons')
    ) AS v(name)
)
SELECT @drift = @drift + COUNT(*)
FROM req
WHERE OBJECT_ID(req.name, N'U') IS NULL;

IF @drift > 0
    PRINT CONCAT('DRIFT: 누락 테이블 ', @drift, ' 개.');

/* 2) 마이그레이션 001 계약: leaderboard.season_id + 인덱스 */
IF COL_LENGTH(N'dbo.leaderboard', N'season_id') IS NULL
BEGIN SET @drift += 1; PRINT 'DRIFT: leaderboard.season_id 누락(마이그 001).'; END

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_leaderboard_season_id_rating'
                 AND object_id = OBJECT_ID(N'dbo.leaderboard'))
BEGIN SET @drift += 1; PRINT 'DRIFT: IX_leaderboard_season_id_rating 누락(마이그 001).'; END

/* 3) 마이그레이션 002 계약: inventory 소프트삭제 컬럼 + 필터드 인덱스 */
IF COL_LENGTH(N'dbo.inventory', N'is_deleted') IS NULL
BEGIN SET @drift += 1; PRINT 'DRIFT: inventory.is_deleted 누락(마이그 002).'; END

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_inventory_active'
                 AND object_id = OBJECT_ID(N'dbo.inventory'))
BEGIN SET @drift += 1; PRINT 'DRIFT: IX_inventory_active 누락(마이그 002).'; END

/* 4) 회귀 가드: 운영 데모 A 가 의존하는 핵심 인덱스가 유지되는지 */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_leaderboard_rating'
                 AND object_id = OBJECT_ID(N'dbo.leaderboard'))
BEGIN SET @drift += 1; PRINT 'REGRESSION: IX_leaderboard_rating 소실(데모 A 영향).'; END

/* 결과 판정 */
IF @drift > 0
    RAISERROR(N'스키마 drift/회귀 %d 건 감지 — 파이프라인 실패.', 16, 1, @drift);
ELSE
    PRINT 'drift-check: 계약 일치. 이상 없음.';
GO
