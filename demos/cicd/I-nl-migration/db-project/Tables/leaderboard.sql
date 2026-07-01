-- leaderboard (랭킹). 데모 I 마이그레이션 001(season_id + 인덱스) 반영.
CREATE TABLE dbo.leaderboard
(
    season       SMALLINT      NOT NULL,
    player_id    BIGINT        NOT NULL,
    rating       INT           NOT NULL CONSTRAINT DF_lb_rating DEFAULT (1000),
    wins         INT           NOT NULL CONSTRAINT DF_lb_wins DEFAULT (0),
    losses       INT           NOT NULL CONSTRAINT DF_lb_losses DEFAULT (0),
    rank_pos     INT           NULL,
    season_id    INT           NULL,
    updated_at   DATETIME2(3)  NOT NULL CONSTRAINT DF_lb_updated DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_leaderboard PRIMARY KEY CLUSTERED (season, player_id),
    CONSTRAINT FK_leaderboard_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id),
    CONSTRAINT FK_leaderboard_seasons FOREIGN KEY (season_id) REFERENCES dbo.seasons (season_id)
);
GO

-- 기존 Top-N 인덱스(라벨 season 기준) — 운영 데모 A 와 호환 유지.
CREATE NONCLUSTERED INDEX IX_leaderboard_rating
    ON dbo.leaderboard (season, rating DESC)
    INCLUDE (player_id, rank_pos, wins, losses);
GO

-- 신규 Top-N 인덱스(정규화 season_id 기준) — 마이그레이션 001.
CREATE NONCLUSTERED INDEX IX_leaderboard_season_id_rating
    ON dbo.leaderboard (season_id, rating DESC)
    INCLUDE (player_id, rank_pos, wins, losses);
GO
