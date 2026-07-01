/* ==========================================================================
   Demo J — 위험 샘플 마이그레이션 #2 (데이터 손실 위험 PR)
   --------------------------------------------------------------------------
   "나쁜 예". PR 리뷰 에이전트가 데이터 손실/보안/롤백 위험을 잡아내는 입력.
   ========================================================================== */
SET NOCOUNT ON;
GO

/* [위험 1] 컬럼 삭제 = 되돌릴 수 없는 데이터 손실.
   - currency_ledger.updated_at 은 감사/디버깅에 쓰이는데 무단 삭제.
   - DACPAC 배포라면 BlockOnPossibleDataLoss 로 막히지만, 명령형 스크립트는 그대로 파괴. */
ALTER TABLE dbo.currency_ledger DROP COLUMN updated_at;
GO

/* [위험 2] 테이블 통째로 재생성(=drop/create) 패턴 — 기존 데이터 소실.
   - "스키마만 바꾸려다" 데이터까지 날림. */
IF OBJECT_ID(N'dbo.leaderboard', N'U') IS NOT NULL
    DROP TABLE dbo.leaderboard;   -- ⚠ 랭킹 데이터 전부 소실
GO
CREATE TABLE dbo.leaderboard
(
    season     SMALLINT NOT NULL,
    player_id  BIGINT   NOT NULL,
    rating     INT      NOT NULL DEFAULT (1000),
    CONSTRAINT PK_leaderboard PRIMARY KEY CLUSTERED (season, player_id)
    -- wins/losses/rank_pos/updated_at 컬럼이 사라짐 = 또 다른 breaking change
);
GO

/* [위험 3] TRUNCATE 로 이력 제거 — 복구 불가. */
TRUNCATE TABLE dbo.matches;
GO
