<#
    cockpit/infra/optional/deploy-ai-foundry.ps1 — Optional LLM inference endpoint
    (Azure AI Foundry / Cognitive Services AIServices). EXECUTION DEFERRED.

    The demo cockpit needs NO Azure resource of its own. This helper only exists
    for the OPTIONAL case where you want the LLM tier hosted in your OWN
    subscription/tenant/region (data-boundary friendly) instead of a local SLM.

    Default behaviour is validate-only (what-if / read-only). Nothing is created
    unless you pass -Execute. No real subscription, resource, or key is ever
    embedded in source — all identifiers are parameters.

    Usage:
        # validate only (default — no changes)
        .\deploy-ai-foundry.ps1 -SubscriptionId <sub> -ResourceGroup rg-mi -AccountName <your-foundry>

        # actually create (only after the environment is confirmed)
        .\deploy-ai-foundry.ps1 -SubscriptionId <sub> -ResourceGroup rg-mi -AccountName <your-foundry> -Execute

        # verify an existing deployment (endpoint + model list)
        .\deploy-ai-foundry.ps1 -SubscriptionId <sub> -ResourceGroup rg-mi -AccountName <your-foundry> -Verify
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SubscriptionId,
    [Parameter(Mandatory = $true)] [string] $ResourceGroup,
    [Parameter(Mandatory = $true)] [string] $AccountName,
    [string] $Location = 'koreacentral',
    [string] $ModelName = 'gpt-4o-mini',
    [string] $ModelVersion = '2024-07-18',
    [string] $DeploymentName = 'gpt-4o-mini',
    [string] $Sku = 'S0',
    [switch] $Execute,
    [switch] $Verify
)

$ErrorActionPreference = 'Stop'

function Test-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI (az) not found. Install it first: https://aka.ms/azure-cli'
    }
}

function Set-Subscription {
    Write-Host "Setting subscription context: $SubscriptionId"
    az account set --subscription $SubscriptionId | Out-Null
}

function Test-AccountExists {
    $existing = az cognitiveservices account show `
        --name $AccountName --resource-group $ResourceGroup `
        --query 'name' -o tsv 2>$null
    return [bool]$existing
}

function Test-DeploymentExists {
    $existing = az cognitiveservices account deployment show `
        --name $AccountName --resource-group $ResourceGroup `
        --deployment-name $DeploymentName --query 'name' -o tsv 2>$null
    return [bool]$existing
}

Test-AzCli
Set-Subscription

if ($Verify) {
    Write-Host "== Verifying $AccountName in $ResourceGroup =="
    if (-not (Test-AccountExists)) {
        Write-Warning "Account '$AccountName' not found. Nothing to verify."
        exit 1
    }
    $endpoint = az cognitiveservices account show `
        --name $AccountName --resource-group $ResourceGroup `
        --query 'properties.endpoint' -o tsv
    Write-Host "Endpoint : $endpoint"
    Write-Host 'Deployments:'
    az cognitiveservices account deployment list `
        --name $AccountName --resource-group $ResourceGroup `
        --query '[].{name:name, model:properties.model.name, version:properties.model.version}' -o table
    Write-Host ''
    Write-Host 'Set these env vars (fetch the key separately, do NOT hardcode):'
    Write-Host "  LLM_ENDPOINT = $endpoint"
    Write-Host "  LLM_API_KEY  = (az cognitiveservices account keys list --name $AccountName --resource-group $ResourceGroup --query key1 -o tsv)"
    Write-Host "  LLM_MODEL    = $DeploymentName"
    exit 0
}

# --- Idempotent create (account) ---
if (Test-AccountExists) {
    Write-Host "Account '$AccountName' already exists — skipping create (idempotent)."
}
else {
    $accountArgs = @(
        'cognitiveservices', 'account', 'create',
        '--name', $AccountName,
        '--resource-group', $ResourceGroup,
        '--location', $Location,
        '--kind', 'AIServices',
        '--sku', $Sku,
        '--custom-domain', $AccountName,
        '--yes'
    )
    if ($Execute) {
        Write-Warning "Creating AIServices account '$AccountName'..."
        az @accountArgs | Out-Null
    }
    else {
        Write-Host '[validate-only] Would run:'
        Write-Host "  az $($accountArgs -join ' ')"
    }
}

# --- Idempotent create (model deployment) ---
$deployArgs = @(
    'cognitiveservices', 'account', 'deployment', 'create',
    '--name', $AccountName,
    '--resource-group', $ResourceGroup,
    '--deployment-name', $DeploymentName,
    '--model-name', $ModelName,
    '--model-version', $ModelVersion,
    '--model-format', 'OpenAI',
    '--sku-name', 'Standard',
    '--sku-capacity', '1'
)

if ($Execute -and (Test-AccountExists) -and (Test-DeploymentExists)) {
    Write-Host "Deployment '$DeploymentName' already exists — skipping (idempotent)."
}
elseif ($Execute) {
    Write-Warning "Creating model deployment '$DeploymentName' ($ModelName $ModelVersion)..."
    az @deployArgs | Out-Null
    Write-Host 'Done. Run again with -Verify to print the endpoint and env vars.'
}
else {
    Write-Host '[validate-only] Would run:'
    Write-Host "  az $($deployArgs -join ' ')"
    Write-Host ''
    Write-Host 'No changes were made. Re-run with -Execute to provision, or -Verify to inspect.'
}
