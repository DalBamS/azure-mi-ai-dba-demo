# B — Deadlock 근본원인 분석

재화·인벤토리 교차 업데이트에서 발생한 deadlock을 AI가 읽기전용 DMV/XE 근거로 분석하고, **상반된 락 순서**를 근본 원인으로 식별한 뒤 안전한 수정 패턴(일관된 락 순서)을 제안하는 운영 데모입니다.

## 연결 이슈
- 유발: `issue-injection\02_blocking_deadlock.sessionA.sql` 와 `sessionB.sql`를 두 창에서 동시에 실행
- 롤백/검증: `issue-injection\02_blocking_deadlock.rollback.sql`
- 정상 부하 패턴: `workload\game-driver\transactions.py`는 낮은 `player_id`부터 잠그는 일관된 락 순서 사용

## 발표 흐름
1. Python 게임 부하를 실행해 정상 트래픽을 만든다.
2. 별도 두 세션에서 `sessionA`와 `sessionB`를 동시에 실행해 deadlock 발생.
3. `01_observe_blocking.sql`로 현재 lock/wait를 관찰.
4. `02_deadlock_evidence.sql`로 system_health XE의 deadlock XML을 수집.
5. AI가 lock order inversion(통화 → 인벤 vs 인벤 → 통화)을 원인으로 설명.
6. `03_eval.sql` 체크리스트로 deadlock graph와 victim/objects를 확인.
7. `04_safe_pattern.sql`의 일관된 락 순서 패턴을 수정안으로 제안.

## 자연어 프롬프트 예시
> 재화 지급 API에서 간헐적으로 1205 deadlock victim이 발생합니다. 어떤 테이블과 트랜잭션 순서가 충돌하는지 근거를 모아 설명하고, 앱 코드와 저장 프로시저 관점에서 안전한 수정안을 제안해 주세요. 변경은 승인 전까지 적용하지 마세요.

## Eval 기준
- deadlock XML에서 `dbo.currency_ledger`와 `dbo.inventory`가 확인됨.
- 두 세션이 반대 순서로 같은 리소스를 잠근 근거가 설명됨.
- 수정안은 모든 경로에서 동일한 lock ordering을 보장함.
