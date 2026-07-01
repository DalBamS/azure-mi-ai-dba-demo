# B — Deadlock 근본원인 분석

재화·인벤토리 교차 업데이트에서 발생한 deadlock을 AI가 읽기전용 DMV/XE 근거로 분석하고, **상반된 락 순서**를 근본 원인으로 식별한 뒤 안전한 수정 패턴(일관된 락 순서)을 제안하는 운영 데모입니다.

## 연결 이슈
- 유발: `issue-injection\02_blocking_deadlock.sessionA.sql` 와 `sessionB.sql`를 두 창에서 동시에 실행
- 롤백/검증: `issue-injection\02_blocking_deadlock.rollback.sql` (주입 데이터), `05_rollback.sql` (데모 생성 proc 정리)
- 정상 부하 패턴: `workload\game-driver\transactions.py`는 낮은 `player_id`부터 잠그는 일관된 락 순서 사용

## 발표 흐름
1. Python 게임 부하를 실행해 정상 트래픽을 만든다.
2. 별도 두 세션에서 `sessionA`와 `sessionB`를 동시에 실행해 deadlock 발생.
3. `01_observe_blocking.sql`로 현재 lock/wait를 관찰.
4. `02_deadlock_evidence.sql`로 system_health XE의 deadlock XML을 수집.
   - **Azure SQL MI/DB 근거**: 데드락 그래프는 system_health의 `ring_buffer`보다 **event_file(.xel)** 타깃에 안정적으로 남습니다. 라이브 MI 검증에서 데드락 47건을 유발했을 때 `ring_buffer` 쿼리는 0건이었지만 `sys.fn_xe_file_target_read_file`로 .xel을 읽으면 `xml_deadlock_report`가 정상 조회됐습니다. 그래서 이 스크립트는 event_file을 우선 읽고 ring_buffer는 폴백으로 UNION 합니다(온프렘/IaaS SQL Server에서는 ring_buffer가 채워지는 경우가 많아 폴백이 유효).
5. AI가 lock order inversion(통화 → 인벤 vs 인벤 → 통화)을 원인으로 설명.
6. `03_eval.sql` 체크리스트로 deadlock graph와 victim/objects를 확인.
7. `04_safe_pattern.sql`의 일관된 락 순서 패턴을 수정안으로 제안.
8. 데모 정리 시 `05_rollback.sql`로 참조용 안전 패턴 proc(`dbo.usp_transfer_gold_safe_example`)을 제거.

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 인지 | 앱 로그의 산발적 1205 에러를 사람이 발견 | "1205 deadlock victim이 난다" 자연어로 접수 |
| 증상 관찰 | `sp_who2`/DMV로 blocking을 손으로 뒤짐, 이미 사라진 경우 재현 난망 | `01_observe_blocking.sql`로 lock/wait를 즉시 스냅샷 |
| 근거 수집 | system_health 링버퍼 XML을 손으로 파싱, deadlock graph 육안 해석 | `02_deadlock_evidence.sql`가 `xml_deadlock_report`를 자동 추출 |
| 원인 판단 | victim·자원·락 순서를 XML에서 눈으로 추적(놓치기 쉬움) | 통화→인벤 vs 인벤→통화 **락 순서 역전**을 근거와 함께 설명 |
| 수정안 | "순서 맞추자"는 구두 합의에 그치기 쉬움 | `04_safe_pattern.sql`의 결정적 락 순서 proc를 참조 패턴으로 제시 |
| 검증(Eval) | 재현이 어려워 "안 나면 고쳐진 것"으로 종결 | `03_eval.sql`로 deadlock XML의 자원·victim을 체크리스트 검증 |

**발표 대본**
> (수동) "데드락은 순간에 사라져서, 예전엔 로그를 뒤지고 링버퍼 XML을 손으로 뜯어보며 어느 트랜잭션이 먼저 무엇을 잠갔는지 눈으로 쫓았습니다. 놓치면 원인 미상으로 남았죠."
> (AI) "하네스는 XEvents deadlock graph를 자동으로 뽑아 '`currency_ledger`와 `inventory`를 두 세션이 반대로 잠갔다'는 락 순서 역전을 근거로 짚습니다. 수정안은 모든 경로에서 동일한 락 순서를 강제하는 안전 패턴이고, 이건 코드 리뷰/승인 대상입니다. 공유 인프라에는 실변경을 자동 적용하지 않습니다."

## 자연어 프롬프트 예시
> 재화 지급 API에서 간헐적으로 1205 deadlock victim이 발생합니다. 어떤 테이블과 트랜잭션 순서가 충돌하는지 근거를 모아 설명하고, 앱 코드와 저장 프로시저 관점에서 안전한 수정안을 제안해 주세요. 변경은 승인 전까지 적용하지 마세요.

## Eval 기준
- deadlock XML에서 `dbo.currency_ledger`와 `dbo.inventory`가 확인됨.
- 두 세션이 반대 순서로 같은 리소스를 잠근 근거가 설명됨.
- 수정안은 모든 경로에서 동일한 lock ordering을 보장함.
