# MCP 라이브 에이전트 셋업 런북 (Azure SQL MI + Entra, 읽기전용)

이 문서는 발표/데모 시 AI 하네스(MCP)를 라이브 Azure SQL Managed Instance에 읽기전용 Entra 인증으로 붙이는 단계별 절차입니다. 서버 구성의 "무엇·왜"는 [README](./README.md), 여기는 "어떻게"에 집중합니다.

## 0. 전제조건

- VS Code + "SQL Server (mssql)" 확장(최신), GitHub Copilot 확장(에이전트 모드).
- Azure CLI(`az`), 필요시 SqlServer PowerShell 모듈.
- Azure SQL MI에 퍼블릭 데이터 엔드포인트 활성화(포트 3342) 또는 프라이빗 엔드포인트+VNet 경로.
- 접속 계정이 MI의 Entra 관리자 또는 DB에 매핑된 사용자.

## 1. 테넌트 확인 (크로스테넌트 함정 주의)

> [!WARNING]
> 라이브 검증에서 실제 겪은 함정: MI가 로그인 신원과 다른 Entra 테넌트에 있으면 기본 토큰으로 못 붙습니다. MI가 속한 테넌트로 명시 로그인합니다.

```powershell
az login --tenant <demo-tenant>.onmicrosoft.com --use-device-code
az account set --subscription <subscription-id>
az account show --query "{sub:id,tenant:tenantId}" -o json
```

## 2. 네트워크: NSG에 3342 인바운드 허용(퍼블릭 엔드포인트)

> [!WARNING]
> MI 퍼블릭 데이터 엔드포인트 활성화만으로는 부족합니다. 서브넷 NSG에 TCP 3342 인바운드 허용 규칙이 없으면 TCP 타임아웃이 납니다. 발표자 IP만 최소 허용합니다.

```powershell
curl.exe -s https://api.ipify.org
az network nsg rule create -g <resource-group> --nsg-name <nsg-name> `
  -n allow_public_endpoint_3342_democlient --priority 1300 `
  --access Allow --protocol Tcp --direction Inbound `
  --source-address-prefixes <presenter-ip>/32 --source-port-ranges '*' `
  --destination-address-prefixes '*' --destination-port-ranges 3342
```

TCP 3342 연결을 테스트합니다.

```powershell
Test-NetConnection <your-mi>.public.<dns-zone>.database.windows.net -Port 3342
```

이 규칙은 임시 인프라이므로 데모/발표 종료 후 삭제합니다.

## 3. Entra 토큰으로 연결 검증(패스워드 없이)

```powershell
$tok = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
Invoke-Sqlcmd -ServerInstance "<your-mi>.public.<dns-zone>.database.windows.net,3342" -Database <gamedb> -AccessToken $tok -TrustServerCertificate -Query "SELECT DB_NAME() db, SUSER_SNAME() login;"
```

`STATISTICS IO` 또는 실행 계획 관련 `InfoMessage`를 확인해야 하면 다음 패턴으로 메시지만 걸러봅니다.

```powershell
Invoke-Sqlcmd -ServerInstance "<your-mi>.public.<dns-zone>.database.windows.net,3342" -Database <gamedb> -AccessToken $tok -TrustServerCertificate -Verbose 4>&1 |
  Where-Object { $_ -match 'logical reads' }
```

## 4. 1순위: VS Code mssql 확장 에이전트 모드 연결(공식)

1. Command Palette -> `MS SQL: Add Connection`.
2. Server: `<your-mi>.public.<dns-zone>.database.windows.net,3342`, Database: `<gamedb>`.
3. Authentication Type: Microsoft Entra ID(구버전 `Azure Active Directory - Universal with MFA`/`Interactive`). 비밀번호는 비우고 브라우저/팝업 로그인.
4. Encrypt=Mandatory, 필요시 Trust server certificate. 프로파일 저장.
5. 연결 후 GitHub Copilot Agent mode에서 자연어로 DMV/메타데이터 질의(내장 mssql MCP 도구). 별도 `npx` 불필요.

팁: `Entra ID` 옵션이 안 보이면 mssql 확장을 최신으로 업데이트합니다. 웹 로그인 팝업이 안 뜨면 Azure: Sign Out -> Sign In을 재시도합니다.

## 5. 2순위: 헤드리스/자동화용 npx MCP 서버(선택)

확장을 못 쓰는 환경(CI, 헤드리스)에서만 사용합니다. `mcp/mcp.config.example.json`을 `mcp.config.json`(git-ignored)으로 복사 후 env를 주입합니다.

| 용도 | 서버 | 메모 |
| --- | --- | --- |
| 기본 예시 | `mssql-mcp-node` | 기본 읽기전용, `MSSQL_ENABLE_WRITES` 미설정 |
| Entra/AAD-only | `@connorbritain/mssql-mcp-server` | `SQL_AUTH_MODE=aad` |
| Azure 리소스/보안 메타 | `@azure/mcp` | Log Analytics/Defender/리소스 메타, 인증은 `az login`/DefaultAzureCredential |

> [!WARNING]
> npm 버전은 빠르게 바뀝니다. 데모 직전 `npm view <pkg> version`으로 재확인합니다. 기준은 [README](./README.md)를 따릅니다.

## 6. 추론 엔드포인트 연결 (SLM/LLM, 자체호스팅/로컬)

MCP가 **데이터**(읽기전용)를 붙이는 계층이라면, 추론 엔드포인트는 **모델**을 붙이는 계층입니다. 근거 수집(MCP) 뒤 해석·리포트 단계에서 SLM/LLM 엔드포인트를 호출합니다. "무엇·왜"는 [README](./README.md)의 추론 엔드포인트 절, 여기는 "어떻게"입니다.

> [!IMPORTANT]
> 엔드포인트 URL·API 키는 **환경변수만** 씁니다(`.env` git-ignored / Key Vault). 코드·config·이 문서에 실값을 넣지 않습니다. 아래는 전부 localhost 플레이스홀더입니다.

1. env 주입(예: 자체호스팅 OpenAI 호환 게이트웨이 또는 로컬 런타임).
   ```powershell
   # SLM (경계 안 로컬): Foundry Local / Ollama
   $env:SLM_ENDPOINT = 'http://localhost:5273/v1/chat/completions'   # OpenAI 호환 예시
   $env:SLM_MODEL    = 'phi-4-mini'

   # LLM (해석/리포트): 자체호스팅=경계 안 / 클라우드=경계 밖 (요건에 맞게 택1)
   $env:LLM_ENDPOINT = 'http://localhost:5273/v1/chat/completions'   # 자체호스팅 예시(플레이스홀더)
   $env:LLM_API_KEY  = '<optional-endpoint-key>'                      # 필요 시에만, env로만
   $env:LLM_MODEL    = '<model-name>'
   ```
2. 엔드포인트 헬스 스모크 테스트(OpenAI 호환 형태).
   ```powershell
   $headers = @{}
   if ($env:LLM_API_KEY) { $headers['Authorization'] = "Bearer $($env:LLM_API_KEY)" }
   $body = @{ model = $env:LLM_MODEL; messages = @(@{ role='user'; content='ping' }); stream = $false } | ConvertTo-Json -Depth 6
   Invoke-RestMethod -Uri $env:LLM_ENDPOINT -Method Post -Headers $headers -Body $body -ContentType 'application/json'
   ```
3. 데모 스크립트가 이 env를 그대로 소비합니다.
   - SLM 배치 린트: `demos/pre-prod/G-sql-preflight-lint/run_batch_lint.ps1` (`SLM_ENDPOINT`/`SLM_API_KEY`).
   - 회귀 리포트: `demos/pre-prod/F-capture-replay-regression/generate_ai_report.ps1` (`LLM_ENDPOINT`/`LLM_API_KEY`/`LLM_MODEL`).

> **경계 원칙**: 스키마/PII/코드가 프롬프트에 들어가는 작업은 **경계 안 엔드포인트**(로컬 SLM 또는 자체호스팅 게이트웨이)를 우선합니다. 클라우드 엔드포인트는 민감 데이터가 없거나 계약·네트워크로 경계가 보장될 때만 env로 전환합니다.

### (선택) Azure AI Foundry 관리형 엔드포인트

자체호스팅 게이트웨이 대신 **Azure AI Foundry에서 키를 발급받아** LLM을 쓰는 경로입니다(위 자체호스팅 예시와 **택1**, 전부 플레이스홀더).

1. Azure AI Foundry 포털에서 **프로젝트/허브 생성**(자체 구독/테넌트/리전).
2. **모델 배포**(예: GPT‑4o mini 등).
3. 배포의 **Endpoint URL**과 **API Key** 확인.
4. env로 주입:
   ```powershell
   $env:LLM_ENDPOINT = 'https://<your-foundry>.services.ai.azure.com/...'   # 포털의 Endpoint URL
   $env:LLM_API_KEY  = '<from-portal>'                                       # 포털의 API Key, env로만
   $env:LLM_MODEL    = '<your-deployment-name>'
   ```

> 프롬프트·데이터가 **내 구독/테넌트/리전 안에 머물고 모델 학습에 사용되지 않으며**, 프라이빗 네트워킹을 붙이면 **경계 안(옵션)** 으로도 운용할 수 있습니다. 리소스명/키/URL은 자리표시자로만 두고 실값은 `.env`(git-ignored)/Key Vault에 둡니다.

### Demo Cockpit Azure AI Foundry 패널

`cockpit/`의 AI 진단 패널은 로컬 SLM 대신 Azure AI Foundry/Azure OpenAI의 OpenAI 호환 chat-completions POST URL을 직접 호출합니다. SQL 실행은 하지 않고, 데모에서 마지막으로 실행한 스텝의 stdout/stderr만 근거로 전달합니다.

```powershell
$env:COCKPIT_MODE = 'live'
$env:COCKPIT_ALLOW_LIVE = '1'
# 전체 chat-completions POST URL — 반드시 /chat/completions 경로여야 함 (Responses API /openai/v1/responses 가 아님)
# 현대 v1 표면: https://<resource>.services.ai.azure.com/openai/v1/chat/completions
# Azure OpenAI 형식도 유효: https://<resource>.openai.azure.com/openai/deployments/<deployment>/chat/completions?api-version=2024-08-01-preview
$env:AI_FOUNDRY_ENDPOINT = 'https://<resource>.services.ai.azure.com/openai/v1/chat/completions'
$env:AI_FOUNDRY_API_KEY = '<from-portal>'
$env:AI_FOUNDRY_DEPLOYMENT = '<your-deployment-name>'
$env:AI_FOUNDRY_AUTH = 'api-key' # or 'bearer'
# (선택) reasoning 모델(gpt-5-mini 등) 사용 시:
$env:AI_FOUNDRY_REASONING_EFFORT = 'minimal'  # minimal|low|medium|high — 빈 응답/고지연 방지
$env:AI_FOUNDRY_MAX_COMPLETION_TOKENS = '2000' # medium/high effort 시 6000+ 권장
# AI_FOUNDRY_TEMPERATURE는 reasoning 모델에서는 설정하지 않음(기본값만 허용)
```

`AI_FOUNDRY_ENDPOINT`는 전체 POST URL입니다. Cockpit 서버는 경로를 덧붙이지 않으며, 키나 전체 URL을 health 응답에 노출하지 않습니다(호스트만 표시).

## 7. 안전/가드레일 체크리스트

- [ ] 진단은 읽기전용 계정/최소권한. 변경(DDL/DML)은 스크립트 제안 -> 사람 승인 -> 적용.
- [ ] config에 커넥션스트링/비밀 하드코딩 금지(env/Key Vault).
- [ ] 추론 엔드포인트 URL/키도 env/Key Vault만. 민감 데이터가 오가면 경계 안 엔드포인트 우선.
- [ ] NSG 3342 임시 규칙은 단일 IP/32, 데모 후 삭제.
- [ ] 공유 MI면 인스턴스 레벨 데모(Defender 알림 등)는 격리/전용 환경에서만.

## 8. 정리(데모 후)

```powershell
az network nsg rule delete -g <resource-group> --nsg-name <nsg-name> -n allow_public_endpoint_3342_democlient
```

MI 퍼블릭 데이터 엔드포인트도 데모 전용이면 비활성화를 고려합니다.
