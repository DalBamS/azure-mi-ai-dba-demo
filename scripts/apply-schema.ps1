<#
    scripts\apply-schema.ps1 — create the game schema and Query Store settings idempotently.
    Reads connection settings from .env / environment (auth-mode aware).

    Usage:
        .\apply-schema.ps1
        .\apply-schema.ps1 -Database gamedb
#>
[CmdletBinding()]
param([string] $Database)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
Import-DotEnv

$repoRoot = Split-Path $PSScriptRoot -Parent
$files = @(
    Join-Path $repoRoot 'schema\ddl\01_tables.sql',
    Join-Path $repoRoot 'schema\ddl\02_indexes.sql',
    Join-Path $repoRoot 'schema\ddl\03_query_store.sql'
)

$connArgs = Get-SqlcmdArgs -Database $Database
foreach ($f in $files) {
    Write-Host "Applying $f ..."
    & sqlcmd @connArgs -b -i $f
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed on $f (exit $LASTEXITCODE)." }
}
Write-Host 'Schema applied.' -ForegroundColor Green
