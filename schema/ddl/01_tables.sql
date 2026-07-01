/* ==========================================================================
   azure-mi-ai-dba-demo — Game schema: tables & constraints
   --------------------------------------------------------------------------
   Target : Azure SQL Managed Instance (T-SQL)
   Run     : against the game database (e.g. gamedb). Connect to that DB first.
   Safety  : IDEMPOTENT — safe to re-run. Only creates objects if missing.
   Notes   : Non-PK/tuning indexes live in 02_indexes.sql so that
             issue-injection (e.g. #1 missing index) can drop & the rollback
             can simply re-run 02_indexes.sql.
   ========================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* --------------------------------------------------------------------------
   players — 계정/프로필 (기준 엔터티)
   -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.players', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.players
    (
        player_id      BIGINT         IDENTITY(1,1) NOT NULL,
        username       NVARCHAR(50)   NOT NULL,
        email          NVARCHAR(256)  NULL,
        region         VARCHAR(16)    NOT NULL CONSTRAINT DF_players_region DEFAULT ('KR'),
        level          INT            NOT NULL CONSTRAINT DF_players_level DEFAULT (1),
        status          TINYINT        NOT NULL CONSTRAINT DF_players_status DEFAULT (1), -- 1=active,0=banned,2=dormant
        created_at     DATETIME2(3)   NOT NULL CONSTRAINT DF_players_created DEFAULT (SYSUTCDATETIME()),
        last_login_at  DATETIME2(3)   NULL,
        CONSTRAINT PK_players PRIMARY KEY CLUSTERED (player_id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'UQ_players_username')
    ALTER TABLE dbo.players
        ADD CONSTRAINT UQ_players_username UNIQUE (username);
GO

/* --------------------------------------------------------------------------
   inventory — 아이템 보유 (핫 테이블, 대량 UPDATE 경합)
   PK (player_id, item_id): 한 플레이어가 아이템별 수량을 보유.
   -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.inventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.inventory
    (
        player_id    BIGINT        NOT NULL,
        item_id      INT           NOT NULL,
        quantity     INT           NOT NULL CONSTRAINT DF_inventory_qty DEFAULT (0),
        acquired_at  DATETIME2(3)  NOT NULL CONSTRAINT DF_inventory_acquired DEFAULT (SYSUTCDATETIME()),
        updated_at   DATETIME2(3)  NOT NULL CONSTRAINT DF_inventory_updated DEFAULT (SYSUTCDATETIME()),
        row_ver      ROWVERSION,
        CONSTRAINT PK_inventory PRIMARY KEY CLUSTERED (player_id, item_id),
        CONSTRAINT CK_inventory_qty CHECK (quantity >= 0)
    );
END
GO

/* --------------------------------------------------------------------------
   currency_ledger — 재화 잔액 (동시성 경합 / blocking·deadlock 지점)
   설계: (player_id, currency_type) 별 현재 잔액을 보관하는 갱신형 테이블.
         재화 이체 트랜잭션이 두 플레이어의 잔액 행을 UPDATE 하며,
         상반된 락 순서로 인해 blocking/deadlock 을 재현한다.
         (append-only 저널이 필요하면 별도 테이블로 확장 가능)
   -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.currency_ledger', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.currency_ledger
    (
        player_id      BIGINT        NOT NULL,
        currency_type  TINYINT       NOT NULL, -- 1=gold,2=gem,3=token
        balance        BIGINT        NOT NULL CONSTRAINT DF_ledger_balance DEFAULT (0),
        updated_at     DATETIME2(3)  NOT NULL CONSTRAINT DF_ledger_updated DEFAULT (SYSUTCDATETIME()),
        row_ver        ROWVERSION,
        CONSTRAINT PK_currency_ledger PRIMARY KEY CLUSTERED (player_id, currency_type),
        CONSTRAINT CK_ledger_balance CHECK (balance >= 0)
    );
END
GO

/* --------------------------------------------------------------------------
   matches — 매치 참여 기록 (대량 INSERT)
   설계: 매치×플레이어 1행. leaderboard 집계의 소스.
   -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.matches', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.matches
    (
        match_id     BIGINT        NOT NULL,
        player_id    BIGINT        NOT NULL,
        mode         VARCHAR(16)   NOT NULL, -- solo, duo, squad, ranked
        score        INT           NOT NULL CONSTRAINT DF_matches_score DEFAULT (0),
        result        TINYINT       NOT NULL, -- 1=win,0=loss,2=draw
        mmr_change   INT           NOT NULL CONSTRAINT DF_matches_mmr DEFAULT (0),
        played_at    DATETIME2(3)  NOT NULL CONSTRAINT DF_matches_played DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_matches PRIMARY KEY CLUSTERED (match_id, player_id)
    );
END
GO

/* --------------------------------------------------------------------------
   leaderboard — 랭킹 (누락 인덱스 시 풀스캔 유발)
   설계: (season, player_id) 별 랭킹 스냅샷. Top-N 조회는 rating 정렬.
         issue #1 이 rating 인덱스를 DROP → 풀스캔.
   -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.leaderboard', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.leaderboard
    (
        season       SMALLINT      NOT NULL,
        player_id    BIGINT        NOT NULL,
        rating       INT           NOT NULL CONSTRAINT DF_lb_rating DEFAULT (1000),
        wins         INT           NOT NULL CONSTRAINT DF_lb_wins DEFAULT (0),
        losses       INT           NOT NULL CONSTRAINT DF_lb_losses DEFAULT (0),
        rank_pos     INT           NULL,
        updated_at   DATETIME2(3)  NOT NULL CONSTRAINT DF_lb_updated DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_leaderboard PRIMARY KEY CLUSTERED (season, player_id)
    );
END
GO

/* --------------------------------------------------------------------------
   Foreign keys (idempotent). NOT trusted checks kept simple for demo seed.
   -------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_inventory_players')
    ALTER TABLE dbo.inventory WITH NOCHECK
        ADD CONSTRAINT FK_inventory_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ledger_players')
    ALTER TABLE dbo.currency_ledger WITH NOCHECK
        ADD CONSTRAINT FK_ledger_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_matches_players')
    ALTER TABLE dbo.matches WITH NOCHECK
        ADD CONSTRAINT FK_matches_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_leaderboard_players')
    ALTER TABLE dbo.leaderboard WITH NOCHECK
        ADD CONSTRAINT FK_leaderboard_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id);
GO

PRINT '01_tables.sql: game schema tables ensured.';
GO
