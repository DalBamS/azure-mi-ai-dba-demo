<#
    scripts\inflate-matches.ps1 — Demo C reversible matches inflation.

    Purpose:
        Demo C primes dbo.usp_matches_summary with a tiny parameter, then reuses that
        cached plan for a typical large-parameter call. Smoke seed data is too small to
        make the underestimated memory grant and resulting sort/hash spills visible, so
        this script adds many FK-safe synthetic matches using existing players.

    Usage:
        .\scripts\inflate-matches.ps1 -Rows 2000000
        .\scripts\inflate-matches.ps1 -Reset
        .\scripts\inflate-matches.ps1 -Rows 2000000 -Database gamedb

    Reset:
        -Reset deletes only synthetic match_id >= 1000000000 rows.

    Notes:
        Demo C setup only. Run -Reset after the presentation.
        No secrets are hardcoded; connection settings come from .env / environment via lib.ps1.
#>
[CmdletBinding()]
param(
    [int] $Rows = 2000000,
    [switch] $Reset,
    [string] $Database
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
Import-DotEnv

if ($Rows -lt 1) { throw "Rows must be >= 1 (got $Rows)." }

$connArgs = Get-SqlcmdArgs -Database $Database

if ($Reset) {
    Write-Warning 'Reset requested: deleting synthetic matches (match_id >= 1000000000)...'
    $resetSql = @'
SET NOCOUNT ON;
DELETE FROM dbo.matches WHERE match_id >= 1000000000;
SELECT
    COUNT(*) AS matches_rows,
    COUNT(CASE WHEN match_id >= 1000000000 THEN 1 END) AS synthetic_rows
FROM dbo.matches;
'@
    & sqlcmd @connArgs -b -Q $resetSql
    if ($LASTEXITCODE -ne 0) { throw "Reset failed (exit $LASTEXITCODE)." }
    Write-Host 'Reset complete (synthetic matches removed).' -ForegroundColor Green
    return
}

$inflateSql = @'
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM dbo.matches WHERE match_id >= 1000000000)
BEGIN
    PRINT 'Synthetic matches already exist (match_id >= 1000000000); skipping inflate.';
END
ELSE
BEGIN
    DECLARE @maxPlayer BIGINT = (SELECT MAX(player_id) FROM dbo.players);
    IF @maxPlayer IS NULL
        THROW 50000, 'Cannot inflate matches: dbo.players has no rows.', 1;

    ;WITH n AS (
        SELECT TOP ($(Rows))
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
        FROM sys.all_objects AS a
        CROSS JOIN sys.all_objects AS b
        CROSS JOIN sys.all_objects AS c
    )
    INSERT dbo.matches (match_id, player_id, mode, score, result, mmr_change)
    SELECT
        1000000000 + rn AS match_id,
        ((rn - 1) % @maxPlayer) + 1 AS player_id,
        CASE rn % 4
            WHEN 0 THEN 'solo'
            WHEN 1 THEN 'duo'
            WHEN 2 THEN 'squad'
            ELSE 'ranked'
        END AS mode,
        ABS(CHECKSUM(NEWID())) % 10000 AS score,
        CAST(rn % 3 AS tinyint) AS result,
        ABS(CHECKSUM(NEWID())) % 101 - 50 AS mmr_change
    FROM n;
END

SELECT
    COUNT(*) AS matches_rows,
    COUNT(CASE WHEN match_id >= 1000000000 THEN 1 END) AS synthetic_rows
FROM dbo.matches;
'@

Write-Host "Inflating matches with $Rows synthetic rows..."
& sqlcmd @connArgs -b -Q $inflateSql -v Rows=$Rows
if ($LASTEXITCODE -ne 0) { throw "Inflate failed (exit $LASTEXITCODE)." }
Write-Host 'Inflate complete. After the demo, run: .\scripts\inflate-matches.ps1 -Reset' -ForegroundColor Green
