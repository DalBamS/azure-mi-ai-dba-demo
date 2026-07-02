<#
    F — generate_ai_report.ps1
    --------------------------------------------------------------------------
    Turn the read-only comparison output of 03_compare_waits.sql (baseline vs
    replay: per-query duration/reads delta + wait-category delta) into a
    natural-language regression report, following the prompt/format contract in
    04_ai_report.md. This is the AI version of a classic DEA regression report.

    It wraps the "concept template" in 04_ai_report.md into a repeatable helper
    you can drop into a pre-flight / CI gate.

    Design notes
      * NO secrets / identifiers hardcoded. The inference endpoint and (optional)
        API key come from environment variables or parameters only. Defaults
        below are generic localhost placeholders, not real infrastructure.
      * Data-boundary aware: this interpretation step is an LLM-class task, but
        the endpoint can be kept INSIDE the data boundary (self-hosted /
        OpenAI-compatible gateway, or a private cloud endpoint) or pointed at a
        managed cloud endpoint. Point -Endpoint / $env:LLM_ENDPOINT wherever it
        must run for your PII / isolation requirements. See mcp/README.md.
      * Read-only against SQL: it consumes *exported* 03 results (a text/CSV/JSON
        file), it does NOT connect to the database. Produce the input by running
        03_compare_waits.sql and saving both result sets to -InputFile.
      * Supports two endpoint shapes:
          - OpenAI  (/v1/chat/completions) e.g. self-hosted gateway / Azure OpenAI / Foundry Local
          - Ollama  (native /api/generate)

    Examples
      # OpenAI-compatible endpoint (default), results exported to a file
      $env:LLM_ENDPOINT = 'http://localhost:5273/v1/chat/completions'
      $env:LLM_API_KEY  = '<optional-endpoint-key>'
      .\generate_ai_report.ps1 -InputFile .\compare-out.txt -TargetLabel 'v17 / BusinessCritical'

      # Local Ollama endpoint
      .\generate_ai_report.ps1 -InputFile .\compare-out.txt -Api Ollama -Model 'phi4'
#>
[CmdletBinding()]
param(
    # Exported output of 03_compare_waits.sql (both result sets as text/CSV/JSON).
    [Parameter(Mandatory = $true)]
    [string] $InputFile,

    # Where to write the generated Korean regression report (Markdown).
    [string] $OutputFile = (Join-Path $PSScriptRoot 'ai_report.generated.md'),

    # Free-text label of the change under test (target tier/version). Placeholder only.
    [string] $TargetLabel = '<대상 버전/티어>',

    # Which endpoint shape to call.
    [ValidateSet('OpenAI', 'Ollama')]
    [string] $Api = 'OpenAI',

    # Model name/tag. Placeholder default; override as needed.
    [string] $Model = 'gpt-4o-mini',

    # Inference endpoint URL. Falls back to env:LLM_ENDPOINT, then a localhost default.
    [string] $Endpoint = $env:LLM_ENDPOINT
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Resolve endpoint (env var / default localhost placeholder — never a real host) ---
if (-not $Endpoint) {
    $Endpoint = if ($Api -eq 'Ollama') {
        'http://localhost:11434/api/generate'
    } else {
        'http://localhost:5273/v1/chat/completions'   # self-hosted / Foundry Local style placeholder
    }
}

# Optional API key for OpenAI-compatible endpoints — env var ONLY, never hardcoded.
$apiKey = $env:LLM_API_KEY

# --- Validate inputs ---
if (-not (Test-Path -LiteralPath $InputFile)) { throw "InputFile not found: $InputFile" }
$compare = Get-Content -LiteralPath $InputFile -Raw
if ([string]::IsNullOrWhiteSpace($compare)) { throw "InputFile is empty: $InputFile" }

function Build-Prompt {
    param([string] $Target, [string] $Compare)
    @"
너는 게임사 DBA를 돕는 성능 회귀 분석가다. 아래는 baseline 대비 replay 워크로드의
Query Store 비교 결과다(1) 쿼리별 duration/reads delta 표, (2) wait-category delta 표).
양수 delta = replay가 baseline보다 느려짐(회귀).

배포 승인 판단을 돕도록 한국어로 요약하라:
(1) 유의미한 회귀가 있는지, (2) 어떤 쿼리/대기유형이 악화됐는지,
(3) 가장 가능성 높은 원인 '가설'(확정 아님)로 명시, (4) 배포 진행/조건부/보류 권고.
반드시 근거 수치를 인용하고, 개선된 항목도 균형 있게 언급하라.
최종 배포 결정은 사람 승인이며, AI는 근거 수집·요약·가설 제시까지임을 전제로 한다.

아래 형식(골격)을 따르되 데이터에 맞게 채워라:

## 배포 전 회귀 검증 리포트 — $Target
- 판정: [진행 가능 / 조건부 / 보류]
- 요약: <상위 N개 중 M개 회귀(평균 +X ms), 개선 K개>

### 회귀 상위
| query_id | base_ms | replay_ms | Δms | 관찰 |
|----------|---------|-----------|-----|------|

### 대기유형 변화
- 가장 커진 대기: <wait_category> (+X ms) → <해석>
- 줄어든 대기: <...>

### 원인 가설
- <...>

### 권고
- <...>

# 비교 결과(03_compare_waits.sql 출력)
$Compare
"@
}

function Invoke-Llm {
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
        if ($apiKey) { $headers['Authorization'] = "Bearer $apiKey" }
        $body = @{
            model    = $Model
            messages = @(
                @{ role = 'system'; content = 'You are a database performance-regression analyst. Answer in Korean, cite numbers, mark causes as hypotheses.' },
                @{ role = 'user';   content = $Prompt }
            )
            temperature = 0
            stream      = $false
        } | ConvertTo-Json -Depth 8
        $resp = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers -Body $body -ContentType 'application/json'
        return $resp.choices[0].message.content
    }
}

Write-Host "Generating regression report from '$InputFile' via $Api @ $Endpoint (model=$Model)" -ForegroundColor Cyan

$prompt = Build-Prompt -Target $TargetLabel -Compare $compare

try {
    $report = Invoke-Llm -Prompt $prompt
}
catch {
    Write-Warning "Inference request failed: $($_.Exception.Message)"
    Write-Warning "Check the endpoint is running and -Endpoint / `$env:LLM_ENDPOINT is correct."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($report)) {
    Write-Warning 'Endpoint returned an empty report.'
    exit 1
}

Set-Content -LiteralPath $OutputFile -Value $report -Encoding UTF8
Write-Host "Done. Report written to: $OutputFile" -ForegroundColor Green
