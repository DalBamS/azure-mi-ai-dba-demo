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

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 인지 | 유저 CS/APM 알람을 보고 "느리다"는 신고를 사람이 접수 | "랭킹이 느리다" 자연어 한 줄을 그대로 입력 |
| 증상 재현 | SSMS를 열고 실제 계획을 손으로 캡처 | `01_reproduce.sql`을 하네스가 실행, 스캔 계획을 자동 첨부 |
| 근거 수집 | `sys.indexes`·missing-index DMV·`dm_exec_query_stats`를 여러 창에서 개별 조회·대조 | `02_diagnose.sql` 한 번으로 인덱스/DMV/IO 근거를 **읽기전용** 수집·요약 |
| 원인 판단 | 경험에 의존해 "인덱스 빠졌네" 추정, 문서화는 별도 | missing-index DMV 근거로 `IX_leaderboard_rating` 누락을 명시 |
| 수정안 | 인덱스 DDL을 손으로 작성(컬럼/INCLUDE 실수 위험) | 정상 스키마와 동일한 DDL(`04_remediate.sql`)을 제안, **사람 승인 전 미적용** |
| 검증(Eval) | "체감상 빨라졌다"로 종료하기 쉬움 | `03_eval.sql` 적용 전/후 logical reads·elapsed를 수치로 대조 |
| 반복 비용 | 매 사건마다 사람이 처음부터 반복 | 값싼 반복은 SLM, 복잡한 해석만 LLM — 사람은 승인에 집중 |

**발표 대본**
> (수동) "예전 같으면 여기서 SSMS 창 서너 개를 띄우고 DMV를 하나씩 붙여가며 '아마 인덱스일 것'이라고 추정했습니다. 근거는 머릿속에, 검증은 감각에 남죠."
> (AI) "지금은 자연어 한 줄이면 하네스가 읽기전용으로 근거를 모아 '`IX_leaderboard_rating` 누락'을 DMV 근거와 함께 짚어줍니다. 변경은 승인 전까지 적용되지 않고, 적용 후에는 logical reads가 실제로 줄었는지 Eval로 증명합니다. DBA는 판단·승인이라는 고부가 작업에 집중합니다."

## 자연어 프롬프트 예시
> 랭킹 화면 Top 100 조회가 갑자기 느려졌습니다. 앱 부하는 계속 흐르고 있고, 최근 스키마 변경 이후부터 발생했습니다. 원인을 진단하고 안전한 수정안을 제안해 주세요. 변경은 승인 전까지 적용하지 마세요.

## Eval 기준
- `IX_leaderboard_rating` 존재.
- Top-N 랭킹 조회가 scan이 아닌 seek/order-friendly index access를 사용.
- `SET STATISTICS IO/TIME` 기준 logical reads가 유의미하게 감소.

## 임팩트 강조 (발표 팁)
> ⚠ 기본 시드 규모(leaderboard가 player당 ~1행, ≤100k)에선 인덱스 DROP 후에도 **wall-clock(경과시간) 차이가 sub-second**라 청중이 체감하기 어려울 수 있습니다. 시간 숫자 대신 아래 **구조적 근거**를 임팩트 포인트로 제시하세요.
>
> 라이브 MI 검증(smoke 시드, leaderboard 992행)에서도 wall-clock은 sub-second였고 논리읽기 차이도 **9 vs 2**로 작게 나왔습니다. 즉 임팩트는 시간이 아니라 **논리읽기(logical reads)와 플랜 형태(Index Seek + 정렬 제거 vs Clustered Index Scan + Sort)**로 보는 것이 정확합니다.
- **논리읽기(logical reads)**: `03_eval.sql`의 `SET STATISTICS IO` 출력에서 인덱스 적용 전(clustered index **Scan**, 전체 페이지 읽기) vs 후(**Seek** + 소수 페이지) 읽기 수가 수십~수백 배 차이 나는 것을 나란히 보여주기.
- **실행계획 연산자**: 적용 전 `Clustered Index Scan` + `Sort` → 적용 후 `Index Seek`(정렬 불필요)로 바뀌는 그림이 가장 설득력 있음.
- **확장성 메시지**: "지금은 데모 규모라 밀리초지만, 이 스캔은 데이터가 커질수록 선형으로 악화된다"로 프로덕션 함의를 연결.
- (선택) 체감 격차를 키우려면 시드를 늘려 데모: 예) 여러 시즌 × 대량 player로 leaderboard를 확장(`schema\seed\01_seed.sql` 규모 조정 또는 반복 INSERT)해 스캔 비용을 물리적으로 키움. 규모 확대 시 데모 후 정리를 잊지 말 것.
