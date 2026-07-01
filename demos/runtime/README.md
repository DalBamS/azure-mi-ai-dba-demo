# 운영(Runtime) 데모

운영 중 발생하는 대표 장애/보안 이벤트를 **이슈 주입 → 읽기전용 진단 → Eval → 사람 승인 → 수정/롤백** 흐름으로 보여주는 발표용 데모팩입니다.

| 코드 | 데모 | 폴더 | 유발 이슈(issue-injection) |
|------|------|------|----------------------------|
| **A** | 느린 쿼리 진단 · 인덱스 추천 | `A-slow-query-index/` | #1 누락 인덱스 랭킹 풀스캔 |
| **B** | Deadlock 근본원인 분석 | `B-deadlock-root-cause/` | #2 Blocking/Deadlock |
| **C** | 패치 후 Plan regression 대응 | `C-plan-regression/` | #3 Plan regression |
| **M** | SQL Injection 탐지 · 진단 | `M-sql-injection/` | #6 SQL Injection 시도 |

## 공통 실행 패턴
1. `issue-injection\*.sql`로 문제를 유발한다.
2. 각 데모 폴더의 `01_*`로 증상을 재현한다.
3. `02_*`로 DMV/XE/메타데이터 근거를 읽기전용 수집한다.
4. `03_eval.sql`로 기준치를 기록한다.
5. 사람 승인 후 `04_*` 수정안을 적용한다.
6. `05_rollback.sql`로 데모 상태를 정리한다.

## AI 하네스 메시지
- **자연어**: “랭킹 조회가 느려졌다”, “1205 deadlock이 난다”, “앱에서만 느리다”, “SQLi 의심 알림이 떴다”.
- **다단계 진단**: DMV/XE/plan cache/audit evidence를 읽기전용으로 수집.
- **Eval**: 적용 전후 logical reads, elapsed time, deadlock graph, 취약 패턴 제거 확인.
- **사람 승인**: 인덱스 생성, proc 수정 같은 변경은 승인 후 별도 스크립트 실행.

값싼 반복은 SLM(Phi-4 로컬), 복잡한 해석은 LLM(클라우드), 연결은 MCP(읽기전용).
