# /mcp — Model Context Protocol 구성 (읽기전용 원칙)

AI 하네스가 안전하게 DB/Azure에 연결하기 위한 MCP 서버 구성을 둡니다.

## 원칙
- **읽기전용 우선**: 진단/조회는 읽기전용 연결로. 변경은 사람 승인 후 별도 경로.
- 비밀은 환경변수/Key Vault. config에 커넥션스트링/비밀 하드코딩 금지.

## 계획된 서버
- **mssql (1순위 · 권장)** — 공식 VS Code **"SQL Server (mssql)" 확장의 GitHub Copilot 에이전트 모드**. 확장 자체가 MCP 툴 호스트라 **별도 npm 서버가 필요 없습니다.** MI에 **Microsoft Entra 인증**으로 연결 프로파일을 만들고 에이전트 모드에서 DMV/메타데이터를 읽기전용 조회합니다(게임사 DBA의 실제 데모 경로).
  - 공식 **Microsoft SQL MCP Server**(Data API Builder 기반, RBAC/telemetry): https://learn.microsoft.com/sql/mcp/
  - **대안(standalone MCP 서버)**: Entra(aad)를 지원하는 커뮤니티 패키지 예시로 `@connorbritain/mssql-mcp-server`(env 예: `SQL_AUTH_MODE=aad`)가 있습니다. **예시일 뿐이며 조직 보안 승인이 필요**합니다. `mcp.config.example.json`에는 `"$disabled": true`로 두었습니다.
- **Azure MCP** (`@azure/mcp`, npm 실재) — Log Analytics, Defender for SQL, 리소스 메타데이터. `npx -y @azure/mcp`, 인증은 `az login` / `DefaultAzureCredential`. 문서: https://github.com/Azure/azure-mcp

## 왜 이렇게 구성했는가 (근거)
라이브 검증 중 npm 확인 결과 기존 config가 참조하던 **`@microsoft/mssql-mcp` 패키지는 존재하지 않았습니다(npm 404).** 반면 `@azure/mcp`는 실재합니다(3.0.0-beta.x). 그래서 존재하지 않는 npx 호출을 제거하고, DB 접속의 1순위를 **공식 VS Code mssql 확장 에이전트 모드**로 명시했습니다 — 이 확장이 곧 MCP 툴 호스트라 별도 서버 프로세스/패키지 관리 없이 Entra 인증만으로 읽기전용 진단이 가능하고, Microsoft가 유지보수하는 공식 경로이기 때문입니다. standalone MCP 서버는 특수 환경을 위한 **대안**으로만 두되, 반드시 실재하는 패키지명과 조직 승인 절차를 전제로 사용합니다.

## 파일
- `mcp.config.example.json` — 서버 목록 + 읽기전용 파라미터 (실값/비밀 금지, standalone mssql은 기본 비활성).
- `README` 내 각 서버별 권한/스코프 설명.
