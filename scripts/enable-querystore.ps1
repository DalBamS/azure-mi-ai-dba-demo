<#
    scripts\enable-querystore.ps1 — enable Query Store for the game database idempotently.
    Reads connection settings from .env / environment (auth-mode aware).

    Usage:
        .\enable-querystore.ps1
        .\enable-querystore.ps1 -Database gamedb
#>
[CmdletBinding()]
param([string] $Database)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
Import-DotEnv

$repoRoot = Split-Path $PSScriptRoot -Parent
$file = Join-Path $repoRoot 'schema\ddl\03_query_store.sql'

$connArgs = Get-SqlcmdArgs -Database $Database
Write-Host "Applying $file ..."
& sqlcmd @connArgs -b -i $file
if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed on $file (exit $LASTEXITCODE)." }

Write-Host 'Query Store status:'
& sqlcmd @connArgs -b -Q "SET NOCOUNT ON; SELECT actual_state_desc, query_capture_mode_desc, interval_length_minutes, flush_interval_seconds, current_storage_size_mb, max_storage_size_mb FROM sys.database_query_store_options;"
if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed while reading Query Store status (exit $LASTEXITCODE)." }

Write-Host 'Query Store enabled.' -ForegroundColor Green
