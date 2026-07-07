# AI로 높이는 Azure SQL Managed Instance 운영 생산성 — 발표 스토리보드

> 대상: 게임사 DBA / 운영 리더 · 발표자: Microsoft Data CSA
> 목적 ①: AI가 DBA 업무 효율을 얼마나 높이는지 체감. 목적 ②: 왜 이 사례가 가능한지(대상 DB 특성 × AI/SLM 특성)를 기술적으로 전달.
> 근거: 이 문서의 수치·실행계획은 라이브 Azure SQL Managed Instance(EngineEdition 8 = MI, v17)에서 실제 검증한 값에 기반합니다. 데모별 상세 대본·수동 vs AI 대비표·Eval 기준은 각 `demos/**/README.md`에 있습니다.

---

## 0. 오프닝(2분) — 왜 지금, 왜 게임 DB인가

- 게임 DB 특성: 핫 테이블의 극심한 동시성(`inventory`·`currency_ledger`), 랭킹/집계(`leaderboard`), 트래픽 급변, PII/결제 데이터. → 운영 이슈가 잦고 반복적이며, 1차 진단이 사람의 시간을 소모합니다.
- 주장: **하네스 엔지니어링** + **L/S 하이브리드(LLM + SLM)** 로 라이프사이클 전체(사전검증 → CI/CD → 운영)를 AI가 감싸면, DBA는 판단·승인에 집중할 수 있습니다.

## 1. 프레임: 하네스 엔지니어링(3분)

공통 패턴:

```
자연어 신고
  → [MCP 읽기전용 DMV/실행계획 수집]
  → [다단계 자동 진단]
  → [Eval: 수정 효과를 수치로 증명]
  → [사람 승인]
  → 적용
```

- **Tools = MCP**: VS Code `mssql` 확장 에이전트 모드(공식 1순위) 읽기전용 연결 + Azure MCP(`@azure/mcp`)로 Log Analytics / Defender 연동.
- **L/S 하이브리드**: 값싼 반복·정적 검증·PII-안전 작업은 로컬 SLM(Phi-4, Foundry Local / Ollama)에서, 복잡한 해석은 LLM에서. → 비용·지연·데이터 경계를 동시에 최적화.
- **실제 AI 경로**: *경로 A* = VS Code Copilot agent + mssql MCP, *경로 B* = **Cockpit AI 진단 패널 → Azure AI Foundry(관리형, 자체 구독/테넌트/리전, API 키)**. 경로 B는 diagnose 스텝 출력을 근거로 Foundry 모델에 진단을 요청하고 후보 DDL을 받습니다(SQL 미실행, 승인 후 적용). 구성: [`cockpit/README.md`](../../cockpit/README.md)
- **Guardrails**: 진단은 읽기전용, DDL/DML은 제안 → 승인 → 적용, 멱등·롤백 보장.
- **왜 가능한가**: MI는 DMV·실행계획·Query Store·XEvents·`sys` 카탈로그로 진단 근거가 구조화되어 있어, 에이전트가 결정론적으로 근거를 수집하고 Eval을 돌릴 수 있습니다. 자연어의 모호함을 수치 Eval로 닫는 것이 핵심입니다.

## 2. 라이프사이클 맵(1분)

| 사전검증 (Pre-prod) | CI/CD | 운영 (Runtime) |
| --- | --- | --- |
| [E 부하 합성](../../demos/pre-prod/E-load-scenario-synthesis/README.md) | [I NL 마이그레이션](../../demos/cicd/I-nl-migration/README.md) | [A 느린 쿼리](../../demos/runtime/A-slow-query-index/README.md) |
| [F 캡처/리플레이](../../demos/pre-prod/F-capture-replay-regression/README.md) | [J PR 위험 리뷰](../../demos/cicd/J-pr-risk-review/README.md) | [B 데드락](../../demos/runtime/B-deadlock-root-cause/README.md) |
| [G SLM 린트](../../demos/pre-prod/G-sql-preflight-lint/README.md) | [K Actions 게이트](../../demos/cicd/K-actions-pipeline/README.md) | [C 플랜 회귀](../../demos/runtime/C-plan-regression/README.md) |
| [O 분류/마스킹](../../demos/pre-prod/O-data-classification-masking/README.md) | | [M 인젝션](../../demos/runtime/M-sql-injection/README.md) |

발표는 운영 **A·B·O** 중심 3막으로 진행하고, 나머지는 맥락으로 짧게 다룹니다.

## 3. 라이브 데모 3막(핵심 15~20분)

### 막1 — [A 느린 랭킹 → 인덱스](../../demos/runtime/A-slow-query-index/README.md) (검증 PASS)

`IX_leaderboard_rating` DROP → 자연어 진단 → 누락 인덱스 지목 → 승인 후 복구 → Eval.

- 실측(smoke): 인덱스 없음일 때 **Clustered Index Seek + Sort / 논리 읽기 9**, 복구 시 **Top + Index Seek(Sort 제거) / 논리 읽기 2**.
- 임팩트는 **실행계획 구조 변화 + 논리 읽기**로 제시합니다(wall-clock은 데이터 규모 확대 시 커짐).

### 막2 — [B 데드락 근본 원인](../../demos/runtime/B-deadlock-root-cause/README.md) (검증 PASS + MI 인사이트)

`sessionA` / `sessionB` 동시 실행(교차 락). 자연어 "이체 간헐 실패(1205)" → 데드락 그래프 캡처·해석 → victim / 락 순서 지목 → 오름차순 락 제안.

- 실측: 데드락 재현, 그래프에서 `currency_ledger` · `inventory` 확인, Eval PASS.
- **MI 심화**:
  - 데드락 그래프는 `system_health` ring_buffer보다 **event_file(`.xel`)** 에서 안정적으로 조회됩니다(`sys.fn_xe_file_target_read_file`).
  - MI에서는 keylock이 한 단계 더 중첩되고, `objectname`에 물리 DB GUID 접두어가 붙습니다(온프렘은 `resource-list` 직속):

    ```xml
    <xactlock>
      <UnderlyingResource>
        <keylock objectname='{physical-db-guid}.dbo.inventory' indexname='PK_inventory'>
      </UnderlyingResource>
    </xactlock>
    ```

### 막3 — [O 분류 + 마스킹 + RLS](../../demos/pre-prod/O-data-classification-masking/README.md) (검증 PASS, 보안 플래그십)

자연어 "PII 점검·마스킹" → 분류 → 승인 후 DDM 마스킹 + `region` RLS → Eval → 롤백.

- 실측: 분류 6건, 저권한 사용자에게 `username` 이 `p***`, RLS 컨텍스트 없음 → 전체 행 / `region=KR` → 일부 행 / 리셋 → 전체 행 (PASS).
- **안전 설계**: RLS 술어는 컨텍스트 미설정 시 전체 허용(부하 드라이버·타 데모에 무영향), `db_owner` 예외 없음.

### (선택) 막 사이 — [C 플랜 회귀](../../demos/runtime/C-plan-regression/README.md) 30초

파라미터 스니핑 개념 소개. 재현에는 규모 / 플랜 분기 쿼리가 필요합니다.

## 4. 라이프사이클 확장(5분 슬라이드)

- **CI/CD ([I](../../demos/cicd/I-nl-migration/README.md) · [J](../../demos/cicd/J-pr-risk-review/README.md) · [K](../../demos/cicd/K-actions-pipeline/README.md))**: 자연어 → 멱등 마이그레이션 + 롤백, PR 위험 리뷰·보안 게이트(과잉 GRANT·마스킹 누락·시크릿 스캔), Actions DACPAC 빌드 → 롤백 대칭성 린트 → drift / 회귀 검사 → 실패 시 Copilot 요약.
- **사전검증 ([E](../../demos/pre-prod/E-load-scenario-synthesis/README.md) · [F](../../demos/pre-prod/F-capture-replay-regression/README.md) · [G](../../demos/pre-prod/G-sql-preflight-lint/README.md))**: Query Store top-query → 부하 합성, 캡처 → 리플레이 회귀, SLM Pre-flight 정적 린트(로컬 Phi-4).

## 5. 정직한 한계(2분)

- **A / C 규모 의존**: smoke는 sub-second이고, C는 현재 쿼리로 재현되지 않습니다 → default 규모 · 플랜 분기 · Query Store 강제 플랜이 필요.
- **공유 인스턴스 주의**: tempdb · 런어웨이 쿼리 · [M 인젝션](../../demos/runtime/M-sql-injection/README.md)은 격리 / 전용 MI에서만.
- 모든 변경은 승인 · 멱등 · 롤백을 전제로 합니다.

## 6. 클로징(1분)

> "AI는 DBA를 대체하지 않는다. 1차 진단·근거 수집·검증을 자동화해 DBA를 판단·승인으로 끌어올린다."

전용 데모 MI + 이 리포로 당장 재현 가능하며, 고객 PoC로 확장할 수 있습니다.

---

## 부록 A — 사전 셋업 런북

- **인증 / 네트워크**: 데모 테넌트 로그인, MI 퍼블릭 엔드포인트(포트 3342), NSG에 발표자 IP 인바운드 허용.
- **DB 준비**: `gamedb` 생성 → schema DDL → seed.
- **클라이언트**: `SqlServer` 모듈 + Entra 액세스 토큰, VS Code `mssql` 확장 에이전트 모드.
- **리허설**: A(drop → 복구), B(2세션 동시), O(적용 → Eval → 롤백).

## 부록 B — 라이브 검증에서 발견·수정된 사항

- seed의 `CHOOSE` + `NEWID` 조합에서 간헐적 NULL 발생 → 결정화.
- child 테이블의 identity 가정 → 실제 `player_id` 참조로 수정, `email` 채움.
- 데모 B: ring_buffer → event_file 로 전환.
- MCP 설정: 존재하지 않는 `@microsoft/mssql-mcp` 제거 → VS Code `mssql` 확장 에이전트 모드 + `@azure/mcp`.
- (모두 `main` 반영 · 라이브 재검증 완료)

## 부록 C — 검증 환경(플레이스홀더)

> 실제 인프라 식별자는 커밋하지 않습니다. 아래 값은 플레이스홀더이며, 구조·규모만 사실입니다.

- **MI**: `<your-mi>.public.<dns-zone>.database.windows.net,3342`
- **EngineEdition**: `8` (Managed Instance)
- **버전**: v17
- **지역**: Korea Central
- **리소스 그룹**: `<resource-group>` · **구독**: `<subscription-id>` · **테넌트**: `<tenant>`

**DB `gamedb` 시드 규모(smoke)**:

| 테이블 | 행 수 |
| --- | --- |
| `players` | 1,000 |
| `currency_ledger` | 3,000 |
| `inventory` | 10,000 |
| `matches` | 5,000 |
| `leaderboard` | ~992 |

> `region`은 5종 균등 분포.
