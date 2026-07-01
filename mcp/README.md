# /mcp — Model Context Protocol 구성 (읽기전용 원칙)

AI 하네스가 안전하게 DB/Azure에 연결하기 위한 MCP 서버 구성을 둡니다.

## 원칙
- **읽기전용 우선**: 진단/조회는 읽기전용 연결로. 변경은 사람 승인 후 별도 경로.
- 비밀은 환경변수/Key Vault. config에 커넥션스트링/비밀 하드코딩 금지.

## 계획된 서버
- **mssql MCP** (VS Code mssql 확장 에이전트 모드) — DB 메타데이터/DMV 읽기전용 조회.
- **Azure MCP** (`microsoft/mcp`) — Log Analytics, Defender for SQL, 리소스 메타데이터.

## 파일 (예정)
- `mcp.config.example.json` — 서버 목록 + 읽기전용 파라미터 (실값 금지).
- `README` 내 각 서버별 권한/스코프 설명.
