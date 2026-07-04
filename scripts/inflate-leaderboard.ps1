<#
    scripts\inflate-leaderboard.ps1 — Demo A reversible row inflation for season=1.

    Purpose:
        Demo A drops IX_leaderboard_rating, then runs:
            SELECT TOP(100) ... FROM dbo.leaderboard WHERE season = 1 ORDER BY rating DESC

        Because PK_leaderboard is clustered on (season, player_id), filtering season=1 is
        still a cheap clustered seek when season=1 has only the smoke-seed rows. The demo
        becomes visible by adding many synthetic rows to season=1 itself: without the
        rating index SQL Server must read all season=1 rows and sort, while remediation
        restores the covering/order-friendly IX_leaderboard_rating path.

    Usage:
        .\scripts\inflate-leaderboard.ps1 -Rows 300000
        .\scripts\inflate-leaderboard.ps1 -Reset
        .\scripts\inflate-leaderboard.ps1 -Rows 300000 -Database gamedb

    Reset:
        -Reset deletes only synthetic player_id > 1000000 leaderboard rows. Original
        season=1 rows and indexes are left untouched.

    Notes:
        Demo A setup only. Run -Reset after the presentation.
        No secrets are hardcoded; connection settings come from .env / environment via lib.ps1.
#>
[CmdletBinding()]
param(
    [int] $Rows = 300000,
    [switch] $Reset,
    [string] $Database
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
Import-DotEnv

if ($Rows -lt 1) { throw "Rows must be >= 1 (got $Rows)." }

$connArgs = Get-SqlcmdArgs -Database $Database

if ($Reset) {
    Write-Warning 'Reset requested: deleting synthetic leaderboard rows (player_id > 1000000)...'
    $resetSql = @'
SET NOCOUNT ON;
DELETE FROM dbo.leaderboard WHERE player_id > 1000000;
SELECT
    COUNT(*) AS leaderboard_rows,
    COUNT(CASE WHEN season = 1 THEN 1 END) AS season_1_rows,
    COUNT(CASE WHEN player_id > 1000000 THEN 1 END) AS synthetic_rows
FROM dbo.leaderboard;
'@
    & sqlcmd @connArgs -b -Q $resetSql
    if ($LASTEXITCODE -ne 0) { throw "Reset failed (exit $LASTEXITCODE)." }
    Write-Host 'Reset complete (synthetic leaderboard rows removed).' -ForegroundColor Green
    return
}

$inflateSql = @'
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM dbo.leaderboard WHERE player_id > 1000000)
BEGIN
    PRINT 'Synthetic leaderboard rows already exist (player_id > 1000000); skipping inflate.';
END
ELSE
BEGIN
    PRINT 'Disabling FK_leaderboard_players for synthetic player_id values...';
    ALTER TABLE dbo.leaderboard NOCHECK CONSTRAINT FK_leaderboard_players;

    BEGIN TRY
        ;WITH n AS (
            SELECT TOP ($(Rows))
                ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
            FROM sys.all_objects AS a
            CROSS JOIN sys.all_objects AS b
            CROSS JOIN sys.all_objects AS c
        )
        INSERT dbo.leaderboard (season, player_id, rating, wins, losses, rank_pos)
        SELECT
            CAST(1 AS smallint) AS season,
            1000000 + rn AS player_id,
            ABS(CHECKSUM(NEWID())) % 4000 + 500 AS rating,
            ABS(CHECKSUM(NEWID())) % 100 AS wins,
            ABS(CHECKSUM(NEWID())) % 100 AS losses,
            NULL AS rank_pos
        FROM n;

        ALTER TABLE dbo.leaderboard CHECK CONSTRAINT FK_leaderboard_players;
    END TRY
    BEGIN CATCH
        ALTER TABLE dbo.leaderboard CHECK CONSTRAINT FK_leaderboard_players;
        THROW;
    END CATCH
END

SELECT
    COUNT(*) AS leaderboard_rows,
    COUNT(CASE WHEN season = 1 THEN 1 END) AS season_1_rows,
    COUNT(CASE WHEN player_id > 1000000 THEN 1 END) AS synthetic_rows
FROM dbo.leaderboard;
'@

Write-Host "Inflating leaderboard season=1 with $Rows synthetic rows..."
& sqlcmd @connArgs -b -Q $inflateSql -v Rows=$Rows
if ($LASTEXITCODE -ne 0) { throw "Inflate failed (exit $LASTEXITCODE)." }
Write-Host 'Inflate complete. After the demo, run: .\scripts\inflate-leaderboard.ps1 -Reset' -ForegroundColor Green
