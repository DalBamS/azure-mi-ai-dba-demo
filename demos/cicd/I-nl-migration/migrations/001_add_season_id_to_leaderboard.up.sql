/* ==========================================================================
   Demo I — Migration 001 UP: leaderboard.season_id 추가 + 인덱스
   --------------------------------------------------------------------------
   Target : Azure SQL Managed Instance (T-SQL)
   Source : 자연어 요구(prompts/nl-request.md 예시 1)에서 AI 하네스가 생성.
   Safety : IDEMPOTENT — 재실행 안전. 온라인/비파괴 우선.
   Rollback: 001_add_season_id_to_leaderboard.down.sql
   Note   : 승인 전 배포 금지. season(SMALLINT) 라벨은 유지, season_id는 정규화 키.
   ========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* --------------------------------------------------------------------------
   1) season 마스터 테이블 (season_id 참조 대상). 없으면 생성.
   -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.seasons', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.seasons
    (
        season_id   INT           IDENTITY(1,1) NOT NULL,
        season      SMALLINT      NOT NULL,      -- 사람이 보는 라벨(기존 값과 정렬)
        name        NVARCHAR(50)  NOT NULL,
        started_at  DATETIME2(3)  NOT NULL CONSTRAINT DF_seasons_started DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_seasons PRIMARY KEY CLUSTERED (season_id),
        CONSTRAINT UQ_seasons_season UNIQUE (season)
    );
    PRINT '001 up: dbo.seasons created.';
END
ELSE
    PRINT '001 up: dbo.seasons already exists (no-op).';
GO

/* season 라벨별 마스터 행 보장(기존 leaderboard.season 값 기준, idempotent) */
INSERT INTO dbo.seasons (season, name)
SELECT DISTINCT lb.season, CONCAT(N'Season ', lb.season)
FROM dbo.leaderboard AS lb
WHERE NOT EXISTS (SELECT 1 FROM dbo.seasons AS s WHERE s.season = lb.season);
GO

/* --------------------------------------------------------------------------
   2) leaderboard.season_id 추가 — NULL 로 추가(메타데이터 전용, 락 최소).
   -------------------------------------------------------------------------- */
IF COL_LENGTH(N'dbo.leaderboard', N'season_id') IS NULL
BEGIN
    ALTER TABLE dbo.leaderboard ADD season_id INT NULL;
    PRINT '001 up: leaderboard.season_id added (NULL).';
END
ELSE
    PRINT '001 up: leaderboard.season_id already exists (no-op).';
GO

/* --------------------------------------------------------------------------
   3) 백필 — 기존 행의 season_id 를 season 라벨로 연결(배치, idempotent).
   -------------------------------------------------------------------------- */
UPDATE lb
   SET lb.season_id = s.season_id
FROM dbo.leaderboard AS lb
JOIN dbo.seasons      AS s ON s.season = lb.season
WHERE lb.season_id IS NULL;
GO

/* --------------------------------------------------------------------------
   4) FK (NOCHECK 로 추가 후 신뢰 체크 — 대형 테이블 스캔/락 회피).
   -------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_leaderboard_seasons')
BEGIN
    ALTER TABLE dbo.leaderboard WITH NOCHECK
        ADD CONSTRAINT FK_leaderboard_seasons
        FOREIGN KEY (season_id) REFERENCES dbo.seasons (season_id);
    PRINT '001 up: FK_leaderboard_seasons added (NOCHECK).';
END
GO

/* --------------------------------------------------------------------------
   5) 신규 Top-N 인덱스 — season_id + rating DESC. 온라인/재개가능(가능 에디션).
      MI General Purpose 는 ONLINE 지원. 실패해도 데모 진행되게 가드.
   -------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_leaderboard_season_id_rating'
                 AND object_id = OBJECT_ID(N'dbo.leaderboard'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX IX_leaderboard_season_id_rating
            ON dbo.leaderboard (season_id, rating DESC)
            INCLUDE (player_id, rank_pos, wins, losses)
            WITH (ONLINE = ON, RESUMABLE = ON);
    END TRY
    BEGIN CATCH
        PRINT '001 up: ONLINE index failed, retrying offline. ' + ERROR_MESSAGE();
        CREATE NONCLUSTERED INDEX IX_leaderboard_season_id_rating
            ON dbo.leaderboard (season_id, rating DESC)
            INCLUDE (player_id, rank_pos, wins, losses);
    END CATCH
    PRINT '001 up: IX_leaderboard_season_id_rating created.';
END
ELSE
    PRINT '001 up: IX_leaderboard_season_id_rating already exists (no-op).';
GO

PRINT '001 up: complete.';
GO
