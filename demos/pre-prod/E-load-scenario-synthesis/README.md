# E — AI 부하 시나리오 합성

자연어 요구("런칭 첫날 동접 5만, 재화 40%/랭킹 30%")를 받아, 실제 **Query Store top query 패턴**을 근거로 현실적인 워크로드 프로파일을 만들고 **game-driver/HammerDB 실행 파라미터**로 자동 변환하는 도입 전(pre-prod) 데모입니다. 다루는 데이터는 전부 **합성(synthetic)** 이라 PII와 무관합니다 — *레코드가 아니라 부하의 형태·규모*를 합성합니다.

## 연결 자산
- 부하 도구: `workload\game-driver`(Python, `WORKLOAD_MIX_*`/`WORKLOAD_CONCURRENCY`), `workload\hammerdb`(TPROC-C, `count_ware`/`num_vu`)
- 근거 소스: Query Store (게임 DB에 `SET QUERY_STORE = ON` 필요)

## 구성 파일
| 파일 | 역할 |
|------|------|
| `01_capture_top_queries.sql` | (읽기전용) QS에서 top query와 카테고리별 실행 비중 추출 |
| `02_synthesize_profile.py` | 자연어 요구 → 믹스/동접을 파싱해 `.env` 스니펫 + HammerDB 파라미터 생성 (stdlib only) |
| `03_eval.sql` | 합성 믹스가 QS 관측 비중과 tolerance(±pp) 내인지 PASS/CHECK |
| `profile.example.env` | 생성 산출물 예시(동접 5만 시나리오) |

## 발표 흐름
1. game-driver/HammerDB로 배경 부하를 얼마간 흘려 Query Store에 데이터를 쌓는다.
2. `01_capture_top_queries.sql`로 "실제로 무엇이 얼마나 도는지"(랭킹/재화/인벤 비중)를 읽는다.
3. 자연어 요구를 합성기에 넣는다:
   ```powershell
   python 02_synthesize_profile.py --request "런칭 첫날 동접 5만, 재화 40%/랭킹 30%" --duration 600 --emit-env profile.env
   ```
4. 출력된 `WORKLOAD_MIX_*`/`WORKLOAD_CONCURRENCY`를 루트 `.env`에 반영하고 `python workload\game-driver\driver.py` 실행, HammerDB는 제안된 `count_ware`/`num_vu` 적용.
5. `03_eval.sql`의 `@req_*`에 합성 믹스를 넣어 관측 비중과의 drift를 PASS/CHECK로 확인.

## 합성 휴리스틱(투명·조정 가능)
- **동접→워커 스레드**: 동접(CCU) 전부가 매 순간 DB를 치지 않음. `threads = clamp(round(CCU × active_ratio), 1, 512)`, 기본 `active_ratio=0.02`. (`--active-ratio`로 조정)
- **HammerDB 베이스라인**: `count_ware = clamp(round(CCU/2500), 4, 200)`, `num_vu = clamp(threads//2, 2, 128)`.
- 발표에서 "이건 데모용 가정이고 현장 수치로 바꿀 수 있다"고 명시하세요.

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 요구 해석 | 기획의 "동접 5만" 문장을 사람이 부하 스펙으로 번역 | 자연어를 그대로 입력, 하네스가 CCU·믹스 의도 추출 |
| 현실성 근거 | 감으로 믹스 비율 추정 | `01`이 QS top query 실제 비중을 근거로 제시 |
| 파라미터화 | 드라이버/HammerDB 값을 손으로 계산·기입(실수·불일치) | `02`가 결정적 매핑으로 `.env`/HammerDB 파라미터 생성 |
| 재현성 | 사람마다 다른 프로파일 | 같은 요구 → 같은 프로파일(결정적) |
| 검증 | "대충 비슷하게 돌렸다" | `03`이 합성 믹스 vs 관측 비중 drift를 수치로 채점 |
| 데이터 리스크 | 실데이터 복제 유혹 | 합성 데이터만 — PII·규정 리스크 원천 차단 |

**발표 대본**
> (수동) "런칭 부하 테스트를 짤 때 제일 애매한 게 '현실적인 믹스'입니다. 기획서의 동접 숫자를 부하 도구 파라미터로 옮기는 건 결국 사람 감이었고, 담당자마다 값이 달랐죠."
> (AI) "하네스는 Query Store가 말해주는 실제 쿼리 비중을 근거로 삼고, 자연어 요구를 결정적으로 드라이버·HammerDB 파라미터로 바꿔줍니다. 같은 요구엔 같은 프로파일이 나오고, 합성한 믹스가 실제와 얼마나 맞는지 Eval로 점수까지 냅니다. 게다가 전부 합성 데이터라 개인정보 리스크가 없습니다."

## Eval 기준
- 합성 믹스의 각 카테고리가 QS 관측 비중 대비 `@tolerance_pp`(기본 ±15pp) 이내면 PASS.
- CHECK는 의도적 divergence(특정 경로 스트레스)일 수도 있으니 맥락으로 해석.

## 정리(cleanup)
- 이 데모는 **읽기전용 + 파일 생성**이라 DB 롤백이 필요 없습니다. 생성한 `profile.env`는 데모 후 삭제하면 됩니다.
- 실행한 부하는 game-driver를 중지(Ctrl+C)하거나 `WORKLOAD_DURATION_SECONDS`로 자동 종료됩니다.
