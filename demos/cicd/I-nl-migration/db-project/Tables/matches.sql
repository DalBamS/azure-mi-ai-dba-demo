-- matches (대량 INSERT, leaderboard 집계 소스).
CREATE TABLE dbo.matches
(
    match_id     BIGINT        NOT NULL,
    player_id    BIGINT        NOT NULL,
    mode         VARCHAR(16)   NOT NULL,
    score        INT           NOT NULL CONSTRAINT DF_matches_score DEFAULT (0),
    result       TINYINT       NOT NULL,
    mmr_change   INT           NOT NULL CONSTRAINT DF_matches_mmr DEFAULT (0),
    played_at    DATETIME2(3)  NOT NULL CONSTRAINT DF_matches_played DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_matches PRIMARY KEY CLUSTERED (match_id, player_id),
    CONSTRAINT FK_matches_players FOREIGN KEY (player_id) REFERENCES dbo.players (player_id)
);
GO

CREATE NONCLUSTERED INDEX IX_matches_player
    ON dbo.matches (player_id) INCLUDE (score, result, mmr_change);
GO

CREATE NONCLUSTERED INDEX IX_matches_played_at
    ON dbo.matches (played_at);
GO
