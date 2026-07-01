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

## 자연어 프롬프트 예시
> 패치 이후 앱에서만 매치 요약 API가 느려졌습니다. SSMS에서 같은 쿼리를 돌리면 괜찮아 보입니다. 앱과 SSMS의 실행계획 차이, SET 옵션, 파라미터 스니핑 여부를 확인하고 안전한 수정안을 제안해 주세요.

## Eval 기준
- `dbo.usp_matches_summary`의 cached plan과 execution stats가 확인됨.
- `set_options`/앱 경로 차이를 설명할 수 있음.
- 수정안은 재컴파일 남발 없이 안정적인 plan 선택을 유도함.
