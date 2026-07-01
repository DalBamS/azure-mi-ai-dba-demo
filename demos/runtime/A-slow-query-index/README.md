# A — 느린 쿼리 진단 · 인덱스 추천

랭킹 Top-N 조회가 느려졌다는 자연어 보고에서 출발해, AI 하네스가 DMV/실행계획 근거를 수집하고 `IX_leaderboard_rating` 누락을 찾아 **인덱스 복구 제안 → Eval → 사람 승인**까지 진행하는 운영 데모입니다.

## 연결 이슈
- 유발: `issue-injection\01_missing_index.sql`
- 롤백: `issue-injection\01_missing_index.rollback.sql`
- 정상 인덱스 정의: `schema\ddl\02_indexes.sql`

## 발표 흐름
1. `issue-injection\01_missing_index.sql` 실행으로 `IX_leaderboard_rating` 삭제.
2. 게임 부하 드라이버를 켠 상태에서 `01_reproduce.sql`로 느린 랭킹 조회 재현.
3. `02_diagnose.sql`로 현재 인덱스, missing-index DMV, 쿼리 통계, IO를 수집.
4. AI가 “`leaderboard(season, rating DESC) INCLUDE (...)` 인덱스 누락”을 제안.
5. `03_eval.sql`로 적용 전 기준치를 기록.
6. 사람 승인 후 `04_remediate.sql` 실행.
7. `03_eval.sql` 재실행으로 읽기량/시간 개선 확인.
8. 데모 정리 시 `05_rollback.sql`은 정상 인덱스가 남아 있음을 보증.

## 자연어 프롬프트 예시
> 랭킹 화면 Top 100 조회가 갑자기 느려졌습니다. 앱 부하는 계속 흐르고 있고, 최근 스키마 변경 이후부터 발생했습니다. 원인을 진단하고 안전한 수정안을 제안해 주세요. 변경은 승인 전까지 적용하지 마세요.

## Eval 기준
- `IX_leaderboard_rating` 존재.
- Top-N 랭킹 조회가 scan이 아닌 seek/order-friendly index access를 사용.
- `SET STATISTICS IO/TIME` 기준 logical reads가 유의미하게 감소.
