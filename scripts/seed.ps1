<#
    scripts\seed.ps1 — generate seed data with a chosen scale profile.
    Overrides the SQL :setvar defaults via sqlcmd -v (which take precedence).

    Profiles (SEED_PROFILE or -Profile):
        default : players=100000 itemsPerPlayer=20 matches=200000
        smoke   : players=1000   itemsPerPlayer=10 matches=5000

    Usage:
        .\seed.ps1                       # profile from .env (SEED_PROFILE) or 'default'
        .\seed.ps1 -Profile smoke
        .\seed.ps1 -Players 5000 -ItemsPerPlayer 15 -Matches 20000
        .\seed.ps1 -Reset                # wipe existing data, then re-seed
#>
[CmdletBinding()]
param(
    [ValidateSet('default', 'smoke')] [string] $Profile,
    [int] $Players,
    [int] $ItemsPerPlayer,
    [int] $Matches,
    [int] $Season = 1,
    [switch] $Reset,
    [string] $Database
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
Import-DotEnv

if (-not $Profile) { $Profile = if ($env:SEED_PROFILE) { $env:SEED_PROFILE } else { 'default' } }

# Profile defaults, overridable by explicit parameters.
switch ($Profile) {
    'smoke'   { $p = 1000;   $i = 10; $m = 5000 }
    default   { $p = 100000; $i = 20; $m = 200000 }
}
if ($Players)        { $p = $Players }
if ($ItemsPerPlayer) { $i = $ItemsPerPlayer }
if ($Matches)        { $m = $Matches }

$connArgs = Get-SqlcmdArgs -Database $Database
$force = 0

if ($Reset) {
    Write-Warning 'Reset requested: deleting existing game data...'
    $resetSql = @'
SET NOCOUNT ON;
DELETE FROM dbo.leaderboard;
DELETE FROM dbo.matches;
DELETE FROM dbo.inventory;
DELETE FROM dbo.currency_ledger;
DELETE FROM dbo.players;
DBCC CHECKIDENT('dbo.players', RESEED, 0);
PRINT 'Reset complete.';
'@
    & sqlcmd @connArgs -b -Q $resetSql
    if ($LASTEXITCODE -ne 0) { throw "Reset failed (exit $LASTEXITCODE)." }
    $force = 1
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$seedFile = Join-Path $repoRoot 'schema\seed\01_seed.sql'

Write-Host "Seeding profile=$Profile players=$p itemsPerPlayer=$i matches=$m ..."
& sqlcmd @connArgs -b -i $seedFile `
    -v SeedPlayers=$p SeedItemsPerPlayer=$i SeedMatches=$m SeedSeason=$Season Force=$force
if ($LASTEXITCODE -ne 0) { throw "Seeding failed (exit $LASTEXITCODE)." }
Write-Host 'Seeding complete.' -ForegroundColor Green
