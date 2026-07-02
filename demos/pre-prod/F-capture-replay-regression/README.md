# F — 워크로드 캡처 → 리플레이 회귀 검증

버전 업그레이드/티어 변경 같은 **도입 전 변경**이 성능 회귀를 일으키는지, 동일 워크로드를 캡처해 대상에 리플레이하고 **wait stats·duration을 비교**해 자연어로 판정하는 데모입니다. 전통적 DEA(Database Experimentation Assistant) 워크플로의 **AI 버전**입니다.

## 전제조건 (Prerequisites)
- **Query Store가 켜져 있어야 합니다.** 비교(`03_compare_waits.sql`)는 Query Store를 유일한 데이터소스로 사용합니다. wait stats까지 비교하려면 **wait statistics capture가 ON**이어야 합니다(기본값 ON). 확인/설정 예시:
  ```sql
  -- 현재 상태 확인
  SELECT actual_state_desc, wait_stats_capture_mode_desc
  FROM sys.database_query_store_options;
  -- 꺼져 있으면 활성화 (플레이스홀더 DB명으로 교체)
  ALTER DATABASE [<your_game_db>] SET QUERY_STORE = ON;
  ALTER DATABASE [<your_game_db>] SET QUERY_STORE (WAIT_STATS_CAPTURE_MODE = ON);
  ```
- baseline·replay 부하가 **Query Store 보존 기간(`stale_query_threshold_days`) 안**에 들어와야 두 구간을 함께 조회할 수 있습니다.

## 데이터소스 관계 — capture(XEvents) ↔ compare(Query Store)
이 데모는 **두 개의 서로 다른 데이터소스**를 씁니다. 역할을 혼동하지 마세요.

| 단계 | 파일 | 데이터소스 | 역할 |
|------|------|-----------|------|
| 캡처 | `01_capture.sql` | **Extended Events**(`demo_capture_replay`) | 리플레이용 **문장 스트림**(rpc/batch completed + sql_text) 확보. ostress/RML로 충실 재생할 때 씀 |
| 비교 | `03_compare_waits.sql` | **Query Store** | baseline vs replay 구간의 **duration·reads·wait delta** 산출(회귀 판정의 실제 근거) |

즉, **XEvents는 "무엇을 다시 돌릴지"(replay 입력)** 를, **Query Store는 "얼마나 느려졌는지"(비교 결과)** 를 담당합니다. 회귀 판정 수치는 XEvents 링버퍼가 아니라 **Query Store에서** 나옵니다. (game-driver를 그대로 재실행하는 권장 데모(옵션 A)에서는 XEvents 스트림 추출이 없어도 되며, XEvents는 옵션 B(ostress/RML)에서만 필수입니다.)

## 구성 파일
| 파일 | 역할 |
|------|------|
| `01_capture.sql` | 서버 XEvents 세션으로 baseline 워크로드(rpc/batch completed) 캡처 |
| `02_replay.md` | 리플레이 방법(game-driver 재실행 / ostress·RML / Distributed Replay) |
| `03_compare_waits.sql` | (읽기전용) baseline vs replay 구간의 쿼리 duration·reads·wait-category delta |
| `04_ai_report.md` | 03 결과 → 자연어 회귀 리포트 생성 프롬프트/형식 |
| `generate_ai_report.ps1` | 04 템플릿을 감싼 헬퍼: 내보낸 03 결과 파일 → 추론 엔드포인트 호출 → 회귀 리포트(md) 생성 (엔드포인트/키는 환경변수만, 비밀 하드코딩 없음) |
| `05_cleanup.sql` | 캡처 XEvents 세션 제거 |

## 발표 흐름
1. `01_capture.sql`로 캡처 세션을 켜고, baseline 부하(game-driver)를 흘린다. **baseline 시작/종료 UTC 시각을 기록**한다.
2. `02_replay.md`대로 **대상 티어/버전**에 동일 부하를 리플레이한다(E의 결정적 프로파일 재사용 권장). **replay 시작/종료 UTC 시각을 기록**한다.
3. `03_compare_waits.sql`의 4개 UTC 변수(`@base_start`/`@base_end`/`@replay_start`/`@replay_end`)를 채워 실행 → 회귀 상위 쿼리와 대기유형 변화를 본다.
4. AI 하네스가 `04_ai_report.md` 템플릿(또는 이를 감싼 `generate_ai_report.ps1`)으로 **자연어 회귀 리포트 + 배포 권고**를 생성. 추론 엔드포인트는 데이터 경계 요건에 따라 자체호스팅/클라우드를 선택([`mcp/README.md`](../../../mcp/README.md)).
5. 데모 후 `05_cleanup.sql`로 캡처 세션 정리.

> **UTC 구간 기록 팁**: 두 구간의 시각은 반드시 **UTC**로 기록하세요. `03_compare_waits.sql`은 `SYSUTCDATETIME()` 기준이며 Query Store의 `runtime_stats_interval.start_time`도 UTC입니다. 부하 실행 직전/직후에 아래로 현재 UTC를 찍어두면 편합니다.
> ```sql
> SELECT SYSUTCDATETIME() AS mark_utc;   -- baseline/replay 시작·종료 시 각각 실행해 기록
> ```

## Query Store 타이밍 주의 (비교 정확도)
- **집계 간격 경계**: Query Store는 `INTERVAL_LENGTH_MINUTES`(기본 60분) 단위로 런타임 통계를 모읍니다. baseline/replay 구간이 **간격 경계에 걸치거나 서로 다른 두 간격에 섞이면** delta가 왜곡될 수 있습니다. 짧고 명확한 부하 구간을 쓰고, 필요하면 간격 길이를 줄이세요:
  ```sql
  ALTER DATABASE [<your_game_db>] SET QUERY_STORE (INTERVAL_LENGTH_MINUTES = 5);
  ```
- **플러시 지연(`DATA_FLUSH_INTERVAL_SECONDS`)**: 통계는 메모리에서 주기적으로 기록됩니다. 부하 종료 **직후** 조회하면 마지막 구간이 아직 안 보일 수 있으니, 비교 쿼리는 잠시(≥ 플러시 간격) 기다렸다 실행하세요.
- **구간 정렬**: `03`은 `rsi.start_time`이 기록한 UTC 창 안에 드는 간격만 집계합니다. baseline과 replay 창이 **겹치지 않도록** 충분한 간격(idle)을 두고 부하를 돌리세요.

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
