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

## 파일
- `mcp.config.example.json` — 서버 목록 + 읽기전용 파라미터 (실값/비밀 금지, mssql은 실재 커뮤니티 서버 `mssql-mcp-node` 예시).
- `README` 내 각 서버별 권한/스코프 설명.
