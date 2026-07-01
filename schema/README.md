# /schema — 게임 스키마 & 시드

## /ddl
게임 데이터베이스의 **idempotent DDL**. 반복 실행해도 안전합니다.

| 파일 | 역할 |
|------|------|
| `ddl\01_tables.sql` | 게임 테이블과 제약 조건 생성 |
| `ddl\02_indexes.sql` | 정상 인덱스 세트 보장 |
| `ddl\03_query_store.sql` | 데모 E가 Query Store에서 게임 쿼리 비중을 읽도록 QS 활성화/설정 |

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
- 프로파일: `default`(대규모), `smoke`(로컬 스모크 테스트).
- 규모는 환경변수/인자로 조절 (`SEED_PLAYERS`, `SEED_ITEMS_PER_PLAYER`, `SEED_MATCHES`).

자세한 실행은 리포지토리 루트 `README.md`의 런북을 참고하세요.
