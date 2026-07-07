<#
    G — run_batch_lint.ps1
    --------------------------------------------------------------------------
    Batch-lint a folder of T-SQL module definitions with a LOCAL SLM (Phi-4급),
    applying the ruleset in 02_lint_rules.md and emitting the JSON output
    contract described there (one array of findings per object).

    This wraps the "concept script" in 03_run_slm_lint.md into a repeatable
    helper you can drop into a CI / pre-flight gate.

    Design notes
      * NO secrets / identifiers hardcoded. Endpoint and (optional) API key come
        from environment variables or parameters only. Values below are generic
        localhost placeholders, not real infrastructure.
      * Supports two local runtimes:
          - Ollama            (native  /api/generate)
          - OpenAI-compatible (/v1/chat/completions) e.g. Foundry Local
      * Read-only against SQL: it lints *files*. Produce the input .sql files
        by exporting result-set 1 of 01_collect_objects.sql (one file per
        object) into -InputDir.

    Examples
      # Ollama (default), lint every *.sql under .\objects
      .\run_batch_lint.ps1 -InputDir .\objects

      # OpenAI-compatible local endpoint (Foundry Local), custom model
      $env:SLM_ENDPOINT = 'http://localhost:5273/v1/chat/completions'
      $env:SLM_API_KEY  = '<optional-local-key>'
      $env:SLM_AUTH     = 'bearer' # or 'api-key' for Azure AI Foundry
      .\run_batch_lint.ps1 -InputDir .\objects -Api OpenAI -Model 'phi-4-mini'
#>
[CmdletBinding()]
param(
    # Folder containing one .sql file per object to lint (module definitions).
    [Parameter(Mandatory = $true)]
    [string] $InputDir,

    # Ruleset file passed to the SLM as the analysis contract.
    [string] $RulesFile = (Join-Path $PSScriptRoot '02_lint_rules.md'),

    # Where to write per-object JSON results + a combined report.
    [string] $OutputDir = (Join-Path $PSScriptRoot 'lint-out'),

    # Which local API shape to call.
    [ValidateSet('Ollama', 'OpenAI')]
    [string] $Api = 'Ollama',

    # Local model name/tag. Placeholder default; override as needed.
    [string] $Model = 'phi4',

    # Local endpoint URL. Falls back to env:SLM_ENDPOINT, then a localhost default.
    [string] $Endpoint = $env:SLM_ENDPOINT,

    # OpenAI-compatible auth header: api-key or bearer. Defaults by endpoint host.
    [string] $AuthHeader = $env:SLM_AUTH
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Resolve endpoint (env var / default localhost placeholder — never a real host) ---
if (-not $Endpoint) {
    $Endpoint = if ($Api -eq 'Ollama') {
        'http://localhost:11434/api/generate'
    } else {
        'http://localhost:5273/v1/chat/completions'   # Foundry Local style placeholder
    }
}

# Optional API key for OpenAI-compatible endpoints — env var ONLY, never hardcoded.
$apiKey = $env:SLM_API_KEY

function Resolve-AuthHeader {
    param([string] $Endpoint, [string] $Requested)

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        $normalized = $Requested.Trim().ToLowerInvariant()
        if ($normalized -notin @('api-key', 'bearer')) {
            throw "AuthHeader must be 'api-key' or 'bearer'."
        }
        return $normalized
    }

    try {
        $host = ([Uri] $Endpoint).Host.ToLowerInvariant()
    }
    catch {
        $host = ''
    }
    if ($host -like '*azure.com') { return 'api-key' }
    return 'bearer'
}

$resolvedAuthHeader = Resolve-AuthHeader -Endpoint $Endpoint -Requested $AuthHeader

# --- Validate inputs ---
if (-not (Test-Path -LiteralPath $InputDir)) { throw "InputDir not found: $InputDir" }
if (-not (Test-Path -LiteralPath $RulesFile)) { throw "RulesFile not found: $RulesFile" }
$files = @(Get-ChildItem -LiteralPath $InputDir -Filter '*.sql' -File)
if ($files.Count -eq 0) { throw "No .sql files found under: $InputDir" }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$rules = Get-Content -LiteralPath $RulesFile -Raw

function Build-Prompt {
    param([string] $Rules, [string] $Definition)
    @"
너는 T-SQL 정적 분석기다. 아래 룰셋(L1~L7)만 사용해 주어진 객체의 안티패턴을 찾아라.
각 발견을 {object, rule, severity, evidence, fix} JSON 배열로만 출력하라(설명 금지).
근거(evidence)는 원문 구절을 인용하라. 확실하지 않으면 포함하지 마라(오탐 최소화).

# 룰셋
$Rules

# 린트 대상 객체 (T-SQL)
$Definition
"@
}

function Invoke-Slm {
    param([string] $Prompt)

    if ($Api -eq 'Ollama') {
        $body = @{
            model  = $Model
            stream = $false
            prompt = $Prompt
        } | ConvertTo-Json -Depth 6
        $resp = Invoke-RestMethod -Uri $Endpoint -Method Post -Body $body -ContentType 'application/json'
        return $resp.response
    }
    else {
        $headers = @{}
        if ($apiKey) {
            if ($resolvedAuthHeader -eq 'api-key') {
                $headers['api-key'] = $apiKey
            } else {
                $headers['Authorization'] = "Bearer $apiKey"
            }
        }
        $body = @{
            model    = $Model
            messages = @(
                @{ role = 'system'; content = 'You are a strict T-SQL static analyzer. Output only JSON.' },
                @{ role = 'user';   content = $Prompt }
            )
            temperature = 0
            stream      = $false
        } | ConvertTo-Json -Depth 8
        $resp = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers -Body $body -ContentType 'application/json'
        return $resp.choices[0].message.content
    }
}

Write-Host "Batch lint: $($files.Count) object(s) via $Api @ $Endpoint (model=$Model)" -ForegroundColor Cyan

$combined = [System.Collections.Generic.List[object]]::new()
$failures = 0

foreach ($f in $files) {
    Write-Host "[lint] $($f.Name)" -ForegroundColor Yellow
    $def = Get-Content -LiteralPath $f.FullName -Raw
    $prompt = Build-Prompt -Rules $rules -Definition $def

    try {
        $raw = Invoke-Slm -Prompt $prompt
    }
    catch {
        Write-Warning "  request failed: $($_.Exception.Message)"
        $failures++
        continue
    }

    $outFile = Join-Path $OutputDir ($f.BaseName + '.json')
    Set-Content -LiteralPath $outFile -Value $raw -Encoding UTF8

    # Best-effort parse so the combined report stays queryable even if a model
    # wraps JSON in prose. We keep the raw text regardless.
    $parsed = $null
    try { $parsed = $raw | ConvertFrom-Json } catch { }
    $combined.Add([pscustomobject]@{
        object   = $f.BaseName
        file     = $f.Name
        findings = $parsed
        raw      = $raw
    })
}

$reportPath = Join-Path $OutputDir 'lint-report.json'
$combined | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host "Done. Per-object JSON in $OutputDir; combined report: $reportPath" -ForegroundColor Green
if ($failures -gt 0) {
    Write-Warning "$failures object(s) failed to lint (endpoint/model issue?)."
    exit 1
}
