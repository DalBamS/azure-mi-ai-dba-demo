-- Declarative final-state (Database-as-Code). 데모 I 마이그레이션 반영본.
CREATE TABLE dbo.players
(
    player_id      BIGINT         IDENTITY(1,1) NOT NULL,
    username       NVARCHAR(50)   NOT NULL,
    email          NVARCHAR(256)  NULL,
    region         VARCHAR(16)    NOT NULL CONSTRAINT DF_players_region DEFAULT ('KR'),
    level          INT            NOT NULL CONSTRAINT DF_players_level DEFAULT (1),
    status         TINYINT        NOT NULL CONSTRAINT DF_players_status DEFAULT (1),
    created_at     DATETIME2(3)   NOT NULL CONSTRAINT DF_players_created DEFAULT (SYSUTCDATETIME()),
    last_login_at  DATETIME2(3)   NULL,
    CONSTRAINT PK_players PRIMARY KEY CLUSTERED (player_id),
    CONSTRAINT UQ_players_username UNIQUE (username)
);
GO

CREATE NONCLUSTERED INDEX IX_players_region
    ON dbo.players (region) INCLUDE (level, status);
GO
