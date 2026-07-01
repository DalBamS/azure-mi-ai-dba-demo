# azure-mi-ai-dba-demo

AI를 활용한 **Azure SQL Managed Instance** DBA 생산성 향상 데모 (게임 워크로드).

AI가 게임 DB의 전 생애주기(**도입 전 검증 → 배포 CI/CD → 운영**)를 감싸는 하나의
**하네스**입니다. 각 단계 공통 패턴: *자연어 → 다단계 자동 진단 → 검증(Eval) → 사람 승인*.
값싼 반복 = **SLM**(Phi-4 로컬), 복잡한 해석 = **LLM**(클라우드), 안전 연결 = **MCP**(읽기전용).
SLM/LLM 결정 근거는 [docs/architecture.md §3](docs/architecture.md#3-역할-분리--slm--llm--mcp)의 표를 따르며, 자동 라우터가 아니라 데모별 배치입니다(예: SLM=G 로컬 린트, LLM=B/F/J 리포트).

> 이 리포지토리는 데모 **자산 전체**를 담습니다. 현재는 **환경 구성**과
> 운영(Runtime) 데모팩 A/B/C/M이 준비된 상태입니다.

## 리포지토리 구조
```
infra/            Azure SQL MI + 보안 스택 (Bicep/az CLI, 파라미터화 — 실행 보류)
schema/ddl/       게임 스키마 DDL (idempotent)
schema/seed/      파라미터화 시드 생성 스크립트
workload/
  hammerdb/       HammerDB TPROC-C 베이스라인 부하 가이드
  game-driver/    Python 게임 부하 드라이버 (OLE DB SET 흉내)
  native/         (선택) C++ MSOLEDBSQL 마이크로 드라이버
issue-injection/  이슈 주입 1~6 + 각 롤백 스크립트
demos/            pre-prod(E/F/G/O), cicd(I/J/K), runtime(A/B/C/M)
mcp/              MCP 서버 config (읽기전용 원칙)
docs/             아키텍처 / 로드맵 / 런북 / 보안
scripts/          헬퍼(prereq 점검, 스키마 적용, 시드)
```

## 데모 환경 스택
- **DB**: Azure SQL Managed Instance (General Purpose 4~8 vCore)
- **게임 스키마**: `players`, `inventory`(핫), `currency_ledger`(동시성 경합), `matches`, `leaderboard`(랭킹)
- **상시 부하**: HammerDB TPROC-C + 게임 특화 Python 드라이버 (재화 이체/인벤 업데이트/랭킹 조회)
- **이슈 주입 카탈로그**: (1)누락 인덱스 풀스캔 (2)Blocking/Deadlock (3)Plan regression (4)tempdb/메모리 압박 (5)런어웨이 쿼리 (6)SQL Injection(격리 MI 한정)
- **보안**: Defender for SQL, SQL Audit→Log Analytics, Vulnerability Assessment, Data Discovery & Classification

---

## 환경 구성 실행 순서 (런북)

> 발표 때 환경 구성 자체는 데모하지 않지만, 실제 운영처럼 트랜잭션이 흐르고 이슈를
> 재현할 수 있어야 합니다. 아래 순서로 한 번 세팅해 둡니다.

### 0. 사전요건
- **PowerShell 7+**, **Python 3.10+**, **ODBC Driver 18 for SQL Server**, **Azure CLI**, **sqlcmd**
- (선택) HammerDB 4.x, C++ 빌드 툴 + MSOLEDBSQL SDK

### 1. 비밀/접속 정보 구성 (하드코딩 금지)
```powershell
Copy-Item .env.example .env
# .env 를 열어 SQLMI_SERVER, AUTH_MODE 등을 채웁니다. 비밀은 Key Vault 권장.
.\scripts\check-prereqs.ps1
```

### 2. (보류) 인프라
실제 Azure 프로비저닝은 **아직 하지 않습니다**. 준비된 Bicep는 검증만 가능:
```powershell
.\infra\deploy.ps1 -SubscriptionId <sub> -WhatIf   # 실행은 환경 확정 후
```

### 3. 스키마
```powershell
.\scripts\apply-schema.ps1        # 01_tables.sql -> 02_indexes.sql -> 03_query_store.sql (idempotent)
```

### 4. 시드 데이터
```powershell
.\scripts\seed.ps1 -Profile smoke     # 로컬 검증(1,000 players)
.\scripts\seed.ps1                     # 데모 규모(default, 100,000 players)
# .\scripts\seed.ps1 -Reset            # 초기화 후 재시드
```

### 5. 상시 부하
```powershell
# (A) 게임 특화 부하 (Python)
cd workload\game-driver
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python driver.py                       # Ctrl+C 까지

# (B) 베이스라인 OLTP — workload\hammerdb\README.md 참고 (HammerDB TPROC-C)
```

### 6. 이슈 주입 (발표 중)
각 이슈를 유발하고, 대응 롤백으로 되돌립니다. 예:
```powershell
# #1 누락 인덱스 -> 랭킹 풀스캔
sqlcmd @(& { . .\scripts\lib.ps1; Import-DotEnv; Get-SqlcmdArgs }) -i issue-injection\01_missing_index.sql
# 롤백
sqlcmd @(& { . .\scripts\lib.ps1; Import-DotEnv; Get-SqlcmdArgs }) -i issue-injection\01_missing_index.rollback.sql
```
> #2(Blocking/Deadlock)는 두 세션 스크립트를 **동시에** 실행합니다. 상세는
> `issue-injection\README.md` 참고. #6(SQL Injection)은 **격리 데모 MI에서만**.

---

## 보안/운영 원칙
- 비밀·커넥션스트링 **하드코딩 금지** → 환경변수/Key Vault (`.env`는 git-ignored).
- MCP/AI 진단은 **읽기전용**. 변경(인덱스 생성 등)은 사람 승인 후 적용.
- 파괴적 작업(이슈 주입, `-Reset`)은 명시적 플래그 필요.

## 발표 자료
- **발표 스토리보드**: [`docs/presentation/storyboard.md`](docs/presentation/storyboard.md) (라이브 MI 실측 근거 기반, 운영 A·B·O 중심 3막).

## 다음 단계
Pre-prod(E/F/G/O) 또는 CI/CD(I/J/K) 데모 구현. 라이프사이클 매핑은 `demos/README.md` 참고.
