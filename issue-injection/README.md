# /issue-injection — 이슈 주입 카탈로그

발표 중 **한 번에 실행**해 문제를 유발하고, 각 이슈를 **되돌리는 롤백** 스크립트를 제공합니다.

| # | 이슈 | 유발 스크립트 | 롤백 |
|---|------|---------------|------|
| 1 | 누락 인덱스 랭킹 풀스캔 | `01_missing_index.sql` | `01_missing_index.rollback.sql` |
| 2 | Blocking / Deadlock (재화·인벤 교차 UPDATE) | `02_blocking_deadlock.*` | `*.rollback.sql` |
| 3 | Plan regression (통계/파라미터 스니핑) | `03_plan_regression.sql` | `03_plan_regression.rollback.sql` |
| 4 | tempdb / 메모리 압박 | `04_tempdb_memory_pressure.sql` | `04_*.rollback.sql` |
| 5 | 런어웨이 쿼리 | `05_runaway_query.sql` | `05_*.rollback.sql` |
| 6 | SQL Injection 시도 (격리 MI 한정) | `06_sql_injection.*` | `06_*.rollback.sql` |

## 원칙
- 각 이슈는 **독립적으로 유발/롤백** 가능해야 함.
- 상태를 바꾸는 스크립트(인덱스 DROP 등)는 반드시 대응 롤백 존재.
- #6은 **격리된 데모 MI에서만** 실행 (프로덕션 금지).
