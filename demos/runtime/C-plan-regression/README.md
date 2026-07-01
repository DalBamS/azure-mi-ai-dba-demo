# C — 패치 후 Plan regression 대응

패치/통계 변경 이후 앱 경로에서만 특정 요약 쿼리가 느려지는 상황을 재현합니다. AI가 plan cache, SET 옵션, parameter sniffing 근거를 모아 “SSMS와 앱의 plan cache가 분리되고 작은 파라미터로 sniff된 plan이 재사용됨”을 설명하고 안전한 수정안을 제안합니다.

## 연결 이슈
- 유발: `issue-injection\03_plan_regression.sql`
- 롤백: `issue-injection\03_plan_regression.rollback.sql`
- 프로덕션 진정성: `workload\game-driver\db.py`가 OLE DB 기본 `ARITHABORT OFF`를 흉내냄

## 발표 흐름
1. `issue-injection\03_plan_regression.sql` 실행으로 sniffed plan 생성.
2. `01_reproduce.sql`로 typical parameter 호출을 반복해 느린 경로 재현.
3. `02_diagnose.sql`로 plan cache, SET 옵션, proc stats 확인.
4. AI가 parameter sniffing + SET option split을 원인으로 설명.
5. `03_eval.sql`로 현재 plan/성능 기준치 확보.
6. 승인 후 `04_remediate.sql`로 안전한 proc 예시(`OPTIMIZE FOR UNKNOWN`) 생성.
7. `05_rollback.sql`로 데모 proc 정리.

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 인지 | "앱에서만 느리다"는 모호한 신고, SSMS에선 빨라 재현 실패 | "패치 후 앱에서만 매치 요약이 느리다" 자연어로 접수 |
| 함정 | SSMS(ARITHABORT ON)로 테스트해 "정상"으로 오판하기 쉬움 | 부하 드라이버(`db.py`, OLE DB **ARITHABORT OFF**)로 앱 경로를 그대로 재현 |
| 근거 수집 | plan cache·`set_options`·proc stats를 손으로 대조 | `02_diagnose.sql`가 cached plan·SET option 비트·proc stats를 한 번에 수집 |
| 원인 판단 | parameter sniffing을 경험으로 의심 | 작은 파라미터로 sniff된 plan 재사용 + SET option 분리를 근거로 설명 |
| 수정안 | 무분별한 `RECOMPILE`/통계 갱신으로 부작용 유발 | `OPTIMIZE FOR UNKNOWN`·plan 강제 등 **안정 plan** 대안을 비교 제시 |
| 검증(Eval) | "이제 빠르네"로 종결 | `03_eval.sql`로 앱 경로 성능·plan을 적용 전후 대조 |

> **진정성 포인트**: 이 데모의 핵심은 부하 드라이버가 프로덕션 C++/MSOLEDBSQL 클라이언트처럼 `ARITHABORT OFF`로 접속한다는 점입니다. 그래서 앱과 SSMS가 **서로 다른 plan-cache 항목**을 갖고, "SSMS에선 빠른데 앱에선 느린" 고전적 현상이 실제로 재현됩니다. 수동 진단이 가장 자주 헛다리 짚는 지점을 하네스가 정확히 겨냥합니다.

**발표 대본**
> (수동) "'앱에서만 느리다'는 신고가 제일 골치입니다. SSMS로 돌려보면 멀쩡하거든요. 예전엔 ARITHABORT 차이를 모르고 몇 시간을 날리기도 했습니다."
> (AI) "하네스는 앱과 동일한 OLE DB SET 옵션 경로로 재현하고, plan cache의 `set_options` 비트와 sniff된 파라미터를 근거로 'SSMS와 앱의 plan이 분리됐다'를 짚습니다. 그리고 재컴파일 남발 대신 안정 plan을 유도하는 수정안을 승인용으로 제안합니다."

## 자연어 프롬프트 예시
> 패치 이후 앱에서만 매치 요약 API가 느려졌습니다. SSMS에서 같은 쿼리를 돌리면 괜찮아 보입니다. 앱과 SSMS의 실행계획 차이, SET 옵션, 파라미터 스니핑 여부를 확인하고 안전한 수정안을 제안해 주세요.

## Eval 기준
- `dbo.usp_matches_summary`의 cached plan과 execution stats가 확인됨.
- `set_options`/앱 경로 차이를 설명할 수 있음.
- 수정안은 재컴파일 남발 없이 안정적인 plan 선택을 유도함.

## 재현 전제조건 (규모/데이터 왜곡 의존성)
> ⚠ 이 데모는 **default 프로파일(matches 200k) 또는 충분한 데이터 규모/왜곡**에서 재현됩니다. 라이브 MI 검증에서 **smoke 프로파일(matches 5,000)** 로 돌렸더니 파라미터 스니핑 회귀가 재현되지 않았습니다: 작은 `@maxPlayer`와 큰 `@maxPlayer`의 실행계획이 동일(Index Seek + Sort + Stream Aggregate)했고 논리읽기도 39로 같았습니다. 즉 데이터가 작으면 어떤 파라미터든 같은 plan이 최적이라 plan이 갈리지 않습니다.

**확정적으로 재현하는 방법 (택1)**
1. **규모 확대(권장, 가장 자연스러움)**: `.\scripts\seed.ps1 -Profile default`(matches 200k)로 시드하거나 `matches`를 충분히 키웁니다. `player_id`가 낮은 값에 몰리도록 분포를 왜곡하면(예: 소수 플레이어가 대량 매치 보유) 작은 `@maxPlayer`는 Index Seek(소수 행)로, 큰 `@maxPlayer`는 Scan + Hash Aggregate가 최적이 되어 plan이 확실히 갈립니다.
2. **Query Store 강제 플랜**: smoke 규모에서도 데모를 확정적으로 연출하려면, 작은 파라미터로 sniff된 plan을 Query Store에서 `sp_query_store_force_plan`으로 강제해 큰 파라미터 호출이 그 plan을 재사용하도록 만들면 회귀를 결정적으로 재현할 수 있습니다.
3. 스키마/쿼리를 바꿔 plan 분기를 강제할 경우, `issue-injection\03_plan_regression.sql` 및 `03_eval.sql`과 정합을 반드시 맞추세요.
