# /mcp — Model Context Protocol 구성 (읽기전용 원칙)

AI 하네스가 안전하게 DB/Azure에 연결하기 위한 MCP 서버 구성을 둡니다.

## 원칙
- **읽기전용 우선**: 진단/조회는 읽기전용 연결로. 변경은 사람 승인 후 별도 경로.
- 비밀은 환경변수/Key Vault. config에 커넥션스트링/비밀 하드코딩 금지.

## 서버 구성 (우선순위)

**1순위 (권장 · 공식, 내장, npx 불필요) — VS Code 'mssql' 확장 에이전트 모드**
- 공식 VS Code **"SQL Server (mssql)" 확장**의 **GitHub Copilot Agent mode**를 사용합니다. 확장에 MCP 도구가 **내장**되어 있어 **별도 npx 패키지가 필요 없습니다.**
- Azure SQL MI에 **Microsoft Entra 인증**으로 연결 프로파일을 만들고, 에이전트 모드에서 DMV/메타데이터를 **읽기전용**으로 조회합니다. 게임사 DBA가 실제로 쓰는 데모 경로입니다.

**2순위 (헤드리스/에이전트용) — 커뮤니티 npx MCP 서버**
- 확장을 못 쓰는 헤드리스/자동화 환경에서는 커뮤니티 npx MCP 서버를 씁니다. 실재 확인된 옵션(작성 시점 버전):
  - **`mssql-mcp-node`** (3.0.0) — **기본 읽기전용**(`MSSQL_ENABLE_WRITES`를 설정하지 않으면 조회 전용). 표준 SQL 접속 env(`MSSQL_SERVER`/`MSSQL_DATABASE`/`MSSQL_USER`/`MSSQL_PASSWORD`/`MSSQL_ENCRYPT`). `mcp.config.example.json`의 기본 예시로 사용.
  - **`@connorbritain/mssql-mcp-server`** (0.6.0) — **Entra/AAD 인증** 지원. SQL 비밀번호 없이 토큰 기반으로 붙이려면 이쪽으로 교체(`SQL_AUTH_MODE=aad`).
- **Entra 토큰 연결**: 필요 시 `az account get-access-token --resource https://database.windows.net/` 로 액세스 토큰을 받아 Entra 인증으로 연결합니다. 접속 계정은 **읽기전용 최소권한**(least privilege)으로 제한하고, 변경(DDL/DML)은 사람 승인 프레임을 거칩니다.
- ⚠️ npm 패키지 버전은 빠르게 바뀝니다. **데모 직전 최신 버전을 재확인**하세요(예: `npm view mssql-mcp-node version`).

**Azure MCP — `@azure/mcp`** (npm 실재, 예: 3.0.0-beta.22)
- Log Analytics, Defender for SQL, 리소스 메타데이터. `npx -y @azure/mcp`, 인증은 `az login` / `DefaultAzureCredential`(config에 비밀 없음). 문서: https://github.com/Azure/azure-mcp

## 왜 이렇게 구성했는가 (근거)
라이브 검증 중 `npm view`로 확인한 결과, 기존 config가 참조하던 **`@microsoft/mssql-mcp` 패키지는 존재하지 않았습니다(npm 404).** 반면 `@azure/mcp`(3.0.0-beta.22), `mssql-mcp-node`(3.0.0), `@connorbritain/mssql-mcp-server`(0.6.0)는 실재합니다. 그래서 존재하지 않는 npx 호출을 제거하고, DB 접속의 **1순위를 공식 VS Code mssql 확장 에이전트 모드**로 명시했습니다 — 확장에 MCP 도구가 내장되어 별도 서버/패키지 관리 없이 Entra 인증만으로 읽기전용 진단이 가능하고 Microsoft가 유지보수하는 공식 경로이기 때문입니다. 헤드리스/에이전트 환경을 위해 **2순위로 실재하는 커뮤니티 npx 서버**를 두되, 읽기전용·env 주입·시크릿 하드코딩 금지 원칙과 사람 승인 프레임을 그대로 유지합니다.

## 추론(Inference) 엔드포인트 — SLM/LLM 모델 연결

MCP가 **데이터 연결**(읽기전용)이라면, 추론 엔드포인트는 **모델 연결**입니다. 하네스는 두 연결을 나눠 봅니다: MCP로 근거(DMV/메타데이터)를 모으고, 추론 엔드포인트(SLM/LLM)로 그 근거를 해석·요약합니다. 데이터 경계 관점의 계층 배치는 [`docs/architecture.md §3`](../docs/architecture.md)을 참고하세요.

**원칙**
- **경계 우선**: 코드/스키마/PII가 프롬프트에 들어가는 작업은 가능한 한 **경계 안 엔드포인트**(로컬 SLM, 또는 자체호스팅 추론 게이트웨이)에서 처리합니다.
- **비밀은 env/Key Vault만**: 엔드포인트 URL·API 키를 config나 스크립트에 하드코딩하지 않습니다. 아래 값들은 **전부 환경변수**로 주입합니다(실값은 `.env`(git-ignored)/Key Vault).

**엔드포인트 종류**

| 용도 | 위치 | 형태 | 환경변수 | 예시 런타임 |
| --- | --- | --- | --- | --- |
| **SLM** (값싼 반복·린트·추출) | 경계 안(로컬) | OpenAI 호환 또는 Ollama 네이티브 | `SLM_ENDPOINT` / `SLM_API_KEY` / `SLM_MODEL` | Foundry Local(`.../v1/chat/completions`), Ollama(`.../api/generate`) |
| **LLM** (복잡한 해석·리포트) | **선택**: 자체호스팅=경계 안 / 클라우드=경계 밖 | OpenAI 호환 또는 Ollama 네이티브 | `LLM_ENDPOINT` / `LLM_API_KEY` / `LLM_MODEL` | 자체호스팅 OpenAI 호환 게이트웨이·VNet 내 프라이빗 엔드포인트, **Azure AI Foundry(관리형, 자체 구독/테넌트/리전, 키 발급)**, 또는 그 밖의 관리형 클라우드 엔드포인트 |

> **자체 엔드포인트(경계 안) 의미**: LLM급 해석도 반드시 퍼블릭 클라우드로 나갈 필요는 없습니다. OpenAI 호환 자체호스팅 게이트웨이(또는 프라이빗 네트워크 경로의 관리형 엔드포인트)를 `LLM_ENDPOINT`로 지정하면 **민감 데이터를 경계 안에 둔 채** 해석 단계를 돌릴 수 있습니다. 기본값은 로컬 플레이스홀더이며, 클라우드 사용은 env로 명시적으로 전환합니다.

**구체 예시 — Azure AI Foundry (관리형, 키 발급)**

사용자가 "AI 키를 발급받아 자체 LLM으로 쓰겠다"는 경우의 대표 경로입니다(전부 플레이스홀더, 실값 하드코딩 금지):

1. Azure AI Foundry 포털에서 **프로젝트/허브 생성**(자체 구독/테넌트/리전).
2. **모델 배포**(예: GPT‑4o mini 등).
3. 배포의 **Endpoint URL**과 **API Key** 확인.
4. env로 주입: `LLM_ENDPOINT=https://<your-foundry>.services.ai.azure.com/...`, `LLM_API_KEY=<from-portal>`, `LLM_MODEL=<your-deployment-name>`.

> 프롬프트·데이터가 **내 구독/테넌트/리전 안에 머물고 모델 학습에 사용되지 않으며**, 프라이빗 네트워킹(프라이빗 엔드포인트/VNet)을 붙이면 **경계 안(옵션)** 으로도 운용할 수 있습니다. 리소스명/키/URL은 위 `<your-foundry-resource>` / `https://<your-foundry>.services.ai.azure.com/...` / `<from-portal>` 같은 자리표시자로만 두고, 실값은 `.env`(git-ignored)/Key Vault에 둡니다.

**Demo Cockpit Azure AI Foundry 패널**

`cockpit/`의 AI 진단 패널은 로컬 모델을 쓰지 않고 Azure AI Foundry/Azure OpenAI의 OpenAI 호환 chat-completions POST URL을 그대로 호출합니다. 실값은 `.env`(git-ignored)/Key Vault로만 주입합니다.

| 환경변수 | 설명 |
| --- | --- |
| `AI_FOUNDRY_ENDPOINT` | 전체 POST URL. 예: `https://<resource>.services.ai.azure.com/models/chat/completions?api-version=2024-05-01-preview` 또는 `https://<resource>.openai.azure.com/openai/deployments/<deployment>/chat/completions?api-version=2024-08-01-preview` |
| `AI_FOUNDRY_API_KEY` | API 키. 코드/문서/config에 실값 금지. |
| `AI_FOUNDRY_DEPLOYMENT` | `body.model`로 보낼 배포/모델 이름. |
| `AI_FOUNDRY_AUTH` | 선택값: `api-key`(기본) 또는 `bearer`. |

라이브 AI 모드는 `COCKPIT_MODE=live`, `COCKPIT_ALLOW_LIVE=1`, `AI_FOUNDRY_ENDPOINT`, `AI_FOUNDRY_API_KEY`가 모두 있을 때만 켜지고, 부족하면 mock 응답으로 폴백합니다. Cockpit은 이 경로에서 SQL을 실행하지 않고 최신 스텝 출력만 근거로 진단 요청을 보냅니다.


**이 env를 쓰는 스크립트**
- [`demos/pre-prod/G-sql-preflight-lint/run_batch_lint.ps1`](../demos/pre-prod/G-sql-preflight-lint/run_batch_lint.ps1) — 로컬 SLM 배치 린트(`SLM_ENDPOINT`/`SLM_API_KEY`).
- [`demos/pre-prod/F-capture-replay-regression/generate_ai_report.ps1`](../demos/pre-prod/F-capture-replay-regression/generate_ai_report.ps1) — 회귀 리포트 생성(`LLM_ENDPOINT`/`LLM_API_KEY`/`LLM_MODEL`), 엔드포인트는 데이터 경계 요건에 따라 자체/클라우드 선택.

라이브 환경에서 엔드포인트를 켜고 검증하는 절차는 [`LIVE-AGENT-SETUP.md`](./LIVE-AGENT-SETUP.md)의 추론 엔드포인트 절을 참고하세요.

## 파일
- [`LIVE-AGENT-SETUP.md`](./LIVE-AGENT-SETUP.md) — 라이브 Azure SQL MI에 Entra 읽기전용 인증으로 연결하는 발표/데모용 단계별 런북.
- `mcp.config.example.json` — 서버 목록 + 읽기전용 파라미터 (실값/비밀 금지, mssql은 실재 커뮤니티 서버 `mssql-mcp-node` 예시).
- `README` 내 각 서버별 권한/스코프 설명.
