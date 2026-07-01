# /schema — 게임 스키마 & 시드

## /ddl
게임 데이터베이스의 **idempotent DDL**. 반복 실행해도 안전합니다.

| 파일 | 역할 |
|------|------|
| `ddl\01_tables.sql` | 게임 테이블과 제약 조건 생성 |
| `ddl\02_indexes.sql` | 정상 인덱스 세트 보장 |
| `ddl\03_query_store.sql` | 데모 E/F가 Query Store에서 게임 쿼리 비중·회귀 근거를 읽도록 QS 활성화/설정 |

| 테이블 | 역할 | 데모 포인트 |
|--------|------|-------------|
| `players` | 계정/프로필 | 기준 엔터티 |
| `inventory` | 아이템 보유 (핫 테이블) | 대량 UPDATE 경합 |
| `currency_ledger` | 재화 원장 | 동시성 경합 / blocking·deadlock |
| `matches` | 매치 기록 | 대량 INSERT |
| `leaderboard` | 랭킹 | 누락 인덱스 시 풀스캔 |

실행 순서: `01_tables.sql` → `02_indexes.sql` → `03_query_store.sql`.
`scripts\apply-schema.ps1`는 세 파일을 이 순서로 모두 적용합니다.

## /seed
현실적 규모의 **파라미터화 시드 생성** 스크립트.
- 정규 실행 방법: `.\scripts\seed.ps1 -Profile default|smoke`. 문서와 발표에서는 `SEED_PROFILE=` 환경변수 표기 대신 이 형식을 사용합니다.
- 프로파일: `default`(대규모), `smoke`(로컬 스모크 테스트).
- 규모 세부값은 명시적 인자(`-Players`, `-ItemsPerPlayer`, `-Matches`)로 조절합니다.

| 데모 | 권장 시드 규모 | 이유 |
|------|----------------|------|
| [A 느린 쿼리·인덱스](../demos/runtime/A-slow-query-index/README.md) | `.\scripts\seed.ps1 -Profile default` 권장 | leaderboard 스캔/Seek 차이를 체감 가능한 구조적 근거로 보여주기 쉬움 |
| [C Plan regression](../demos/runtime/C-plan-regression/README.md) | `.\scripts\seed.ps1 -Profile default` 권장 | 작은 smoke 규모에서는 파라미터별 plan이 갈리지 않을 수 있음 |
| 나머지 데모(B/E/F/G/O/I/J/K/M) | `.\scripts\seed.ps1 -Profile smoke`로 충분 | 기능 검증·런북 시연에는 빠른 smoke 규모가 충분하며, 필요 시 default로 확장 |

자세한 실행은 리포지토리 루트 `README.md`의 런북을 참고하세요.
