# F — 워크로드 캡처 → 리플레이 회귀 검증

버전 업그레이드/티어 변경 같은 **도입 전 변경**이 성능 회귀를 일으키는지, 동일 워크로드를 캡처해 대상에 리플레이하고 **wait stats·duration을 비교**해 자연어로 판정하는 데모입니다. 전통적 DEA(Database Experimentation Assistant) 워크플로의 **AI 버전**입니다.

## 구성 파일
| 파일 | 역할 |
|------|------|
| `01_capture.sql` | 서버 XEvents 세션으로 baseline 워크로드(rpc/batch completed) 캡처 |
| `02_replay.md` | 리플레이 방법(game-driver 재실행 / ostress·RML / Distributed Replay) |
| `03_compare_waits.sql` | (읽기전용) baseline vs replay 구간의 쿼리 duration·reads·wait-category delta |
| `04_ai_report.md` | 03 결과 → 자연어 회귀 리포트 생성 프롬프트/형식 |
| `05_cleanup.sql` | 캡처 XEvents 세션 제거 |

## 발표 흐름
1. `01_capture.sql`로 캡처 세션을 켜고, baseline 부하(game-driver)를 흘린다. 구간 UTC 시각 기록.
2. `02_replay.md`대로 **대상 티어/버전**에 동일 부하를 리플레이한다(E의 결정적 프로파일 재사용 권장). 구간 UTC 시각 기록.
3. `03_compare_waits.sql`의 4개 시각 변수를 채워 실행 → 회귀 상위 쿼리와 대기유형 변화를 본다.
4. AI 하네스가 `04_ai_report.md` 템플릿으로 **자연어 회귀 리포트 + 배포 권고**를 생성.
5. 데모 후 `05_cleanup.sql`로 캡처 세션 정리.

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 캡처 | Profiler/트레이스를 수동 구성 | `01`이 XEvents 캡처 세션을 표준화 |
| 리플레이 | 재현 부하를 매번 손으로 맞춤(믹스 불일치) | E의 결정적 프로파일로 baseline=replay 보장 |
| 비교 | 두 구간 DMV/QS를 눈으로 대조 | `03`이 duration·reads·wait delta를 자동 산출 |
| 해석 | 표를 사람이 해석·문서화 | `04`가 근거 인용 자연어 리포트로 요약 |
| 판정 | "느려진 것 같다"는 주관 | 회귀 상위 + wait 변화 근거로 진행/보류 권고 |
| 정리 | 트레이스 남아 서버 부담 | `05`가 캡처 세션 확실히 제거 |

**발표 대본**
> (수동) "업그레이드 전에 회귀를 보려면 트레이스를 뜨고, 두 번 돌리고, 결과를 엑셀로 옮겨 눈으로 비교했습니다. 리플레이 부하가 매번 미묘하게 달라 비교가 흔들렸죠."
> (AI) "하네스는 같은 프로파일로 baseline과 replay를 재현하고, Query Store에서 쿼리별·대기유형별 delta를 뽑아 '무엇이 얼마나 느려졌는지'를 근거와 함께 자연어로 요약합니다. DBA는 배포 진행/보류라는 결정에 집중합니다."

## Eval 기준
- `03_compare_waits.sql`에서 회귀 상위 쿼리의 `duration_delta_ms`가 허용치 이내인지 확인.
- 커진 wait category가 설명 가능한지(예: 병렬성/락/IO), 개선 항목과 균형 있게 해석.

## 정리(cleanup)
- `05_cleanup.sql`로 `demo_capture_replay` XEvents 세션 제거. Query Store 데이터는 정상 텔레메트리이므로 유지.
