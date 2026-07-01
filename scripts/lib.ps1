<#
    scripts\lib.ps1 — shared helpers: load .env and build sqlcmd arguments.
    Dot-source this from other scripts:  . "$PSScriptRoot\lib.ps1"
    NO secrets are hardcoded; everything comes from .env / environment / Key Vault.
#>

function Import-DotEnv {
    param([string] $Path)
    if (-not $Path) { $Path = Join-Path (Split-Path $PSScriptRoot -Parent) '.env' }
    if (-not (Test-Path $Path)) {
        Write-Verbose "No .env at $Path (using existing environment variables)."
        return
    }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = Remove-DotEnvInlineComment $line.Substring($idx + 1)
        [Environment]::SetEnvironmentVariable($key, $val, 'Process')
    }
    Write-Verbose "Loaded environment from $Path"
}

function Remove-DotEnvInlineComment {
    param([string] $Value)

    $inSingleQuote = $false
    $inDoubleQuote = $false
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $ch = $Value[$i]
        if ($ch -eq "'" -and -not $inDoubleQuote) {
            $inSingleQuote = -not $inSingleQuote
        } elseif ($ch -eq '"' -and -not $inSingleQuote) {
            $inDoubleQuote = -not $inDoubleQuote
        } elseif ($ch -eq '#' -and -not $inSingleQuote -and -not $inDoubleQuote) {
            return $Value.Substring(0, $i).Trim().Trim('"').Trim("'")
        }
    }

    return $Value.Trim().Trim('"').Trim("'")
}

function Get-KeyVaultSecret {
    param([string] $VaultName, [string] $SecretName)
    if (-not $VaultName -or -not $SecretName) { return '' }
    try {
        return (az keyvault secret show --vault-name $VaultName --name $SecretName --query value -o tsv)
    } catch {
        Write-Warning "Key Vault secret '$SecretName' unavailable: $_"
        return ''
    }
}

# Build the sqlcmd argument array from environment (auth-mode aware).
function Get-SqlcmdArgs {
    param([string] $Database)

    $server = $env:SQLMI_SERVER
    if (-not $server) { throw 'SQLMI_SERVER is not set (configure .env; never hardcode).' }
    $port = if ($env:SQLMI_PORT) { $env:SQLMI_PORT } else { '1433' }
    $db   = if ($Database) { $Database } elseif ($env:SQLMI_DATABASE) { $env:SQLMI_DATABASE } else { 'gamedb' }
    $authMode = if ($env:AUTH_MODE) { $env:AUTH_MODE.ToLower() } else { 'aad-integrated' }

    $args = @('-S', "tcp:$server,$port", '-d', $db, '-N')  # -N = encrypt
    if ($env:ODBC_TRUST_SERVER_CERT -eq 'yes') { $args += '-C' }

    switch ($authMode) {
        'sql' {
            $pwd = $env:SQL_PASSWORD
            if (-not $pwd -and $env:KEYVAULT_NAME) {
                $pwd = Get-KeyVaultSecret -VaultName $env:KEYVAULT_NAME -SecretName ($env:KEYVAULT_SECRET_SQL_PASSWORD ?? 'sqlmi-admin-password')
            }
            $args += @('-U', $env:SQL_USER, '-P', $pwd)
        }
        'aad-password' {
            $args += @('-G', '-U', $env:SQL_USER, '-P', $env:SQL_PASSWORD)
        }
        default {
            # aad-integrated (and, best-effort, aad-service-principal via az context)
            $args += '-G'
        }
    }
    return $args
}
