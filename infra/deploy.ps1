<#
    infra\deploy.ps1 — SQL MI deployment wrapper (EXECUTION DEFERRED).
    Prepares/validates the Bicep deployment. Do NOT run until the target
    environment is confirmed. Secrets come from Key Vault (see parameters file),
    never from the command line or source.

    Usage (later):
        .\deploy.ps1 -SubscriptionId <sub> -WhatIf        # validate only
        .\deploy.ps1 -SubscriptionId <sub>                # actually deploy
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SubscriptionId,
    [string] $Location = 'koreacentral',
    [string] $ParametersFile = "$PSScriptRoot\main.parameters.example.json",
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'

Write-Host "Setting subscription context: $SubscriptionId"
az account set --subscription $SubscriptionId

$deploymentName = "gamedemo-$((Get-Date).ToString('yyyyMMddHHmmss'))"
$common = @(
    'deployment', 'sub', 'create',
    '--name', $deploymentName,
    '--location', $Location,
    '--template-file', "$PSScriptRoot\main.bicep",
    '--parameters', "@$ParametersFile"
)

if ($WhatIf) {
    Write-Host 'Running what-if (no changes will be made)...'
    az @common --what-if
} else {
    Write-Warning 'Provisioning SQL MI can take a long time. Proceeding...'
    az @common
}
