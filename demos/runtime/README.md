# 운영(Runtime) 데모

> Placeholder — 이후 세션에서 자산을 채웁니다.

| 코드 | 데모 | 유발 이슈(issue-injection) |
|------|------|----------------------------|
| **A** | 느린 쿼리 진단 · 인덱스 추천 | #1 누락 인덱스 랭킹 풀스캔 |
| **B** | Deadlock 근본원인 분석 | #2 Blocking/Deadlock (재화·인벤 교차 UPDATE) |
| **C** | 패치 후 Plan regression 대응 | #3 Plan regression |
| **M** | SQL Injection 탐지 · 진단 | #6 SQL Injection 시도 |

## 공통 패턴
자연어 → 다단계 자동 진단 → Eval → 사람 승인.
값싼 반복은 SLM(Phi-4 로컬), 복잡한 해석은 LLM(클라우드), 연결은 MCP(읽기전용).
