-- seasons (마스터). 데모 I 마이그레이션 001 로 추가된 정규화 대상.
CREATE TABLE dbo.seasons
(
    season_id   INT           IDENTITY(1,1) NOT NULL,
    season      SMALLINT      NOT NULL,
    name        NVARCHAR(50)  NOT NULL,
    started_at  DATETIME2(3)  NOT NULL CONSTRAINT DF_seasons_started DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_seasons PRIMARY KEY CLUSTERED (season_id),
    CONSTRAINT UQ_seasons_season UNIQUE (season)
);
GO
