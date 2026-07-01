<#
    scripts\check-prereqs.ps1 — verify local tooling for the demo environment.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot\lib.ps1"

$ok = $true
function Test-Cmd {
    param([string] $Name, [string] $Hint)
    $found = Get-Command $Name -ErrorAction SilentlyContinue
    if ($found) { Write-Host "[ok]   $Name" -ForegroundColor Green }
    else { Write-Host "[MISS] $Name — $Hint" -ForegroundColor Yellow; $script:ok = $false }
}

Write-Host 'Checking prerequisites...'
Test-Cmd 'sqlcmd' 'Install SQL command-line tools (go-sqlcmd or ODBC-based sqlcmd).'
Test-Cmd 'python' 'Install Python 3.10+ for the game load driver.'
Test-Cmd 'az'     'Install Azure CLI (used for Key Vault + infra deploy).'

# ODBC Driver 18 presence (Windows registry check).
$odbc = Get-ChildItem 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -like 'ODBC Driver 1*for SQL Server' }
if ($odbc) { Write-Host "[ok]   ODBC Driver for SQL Server" -ForegroundColor Green }
else { Write-Host '[MISS] ODBC Driver 18 for SQL Server — install MSODBCSQL18.' -ForegroundColor Yellow; $ok = $false }

Import-DotEnv
if ($env:SQLMI_SERVER) { Write-Host "[ok]   SQLMI_SERVER is set" -ForegroundColor Green }
else { Write-Host '[warn] SQLMI_SERVER not set — copy .env.example to .env and fill it in.' -ForegroundColor Yellow }

if ($env:SQLMI_SERVER -and (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    try {
        $connArgs = Get-SqlcmdArgs -Database $env:SQLMI_DATABASE
        $state = (& sqlcmd @connArgs -h -1 -W -Q "SET NOCOUNT ON; SELECT actual_state_desc FROM sys.database_query_store_options;")
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd exited with $LASTEXITCODE" }
        $state = ($state | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
        if ($state -eq 'READ_WRITE') {
            Write-Host "[ok]   gamedb Query Store is READ_WRITE" -ForegroundColor Green
        } else {
            Write-Host "[warn] gamedb Query Store is '$state' — run scripts\enable-querystore.ps1." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[warn] Could not read gamedb Query Store state — run scripts\enable-querystore.ps1 after connectivity is available. $_" -ForegroundColor Yellow
    }
}

if ($ok) { Write-Host 'Prerequisites look good.' -ForegroundColor Green }
else { Write-Host 'Some prerequisites are missing (see above).' -ForegroundColor Yellow; exit 1 }
