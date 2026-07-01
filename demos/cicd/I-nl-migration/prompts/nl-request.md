# 자연어 요구 (데모 I 입력)

발표자는 아래 자연어 한 줄만 하네스에 던진다. 하네스는 이를 **idempotent 마이그레이션 +
롤백 스크립트**(그리고 SQL Database Project 변경)로 자동 변환한다.

## 프롬프트 예시 1 — leaderboard 시즌 파티셔닝 키 추가 (주 예시)
> `leaderboard`에 `season_id INT`를 추가해서 시즌별로 랭킹을 분리하고 싶습니다.
> 기존 `season SMALLINT`은 사람이 보는 라벨로 유지하되, 신규 `season_id`는 시즌 마스터를
> 가리키는 정규화 키입니다. Top-N 조회가 `season_id` + `rating DESC`로 빨라지도록 인덱스도
> 같이 넣어 주세요. 운영 중 무중단으로 적용 가능해야 하고, 문제가 생기면 되돌릴 수 있는
> 롤백 스크립트도 함께 만들어 주세요. **승인 전에는 배포하지 마세요.**

기대 산출물:
- `migrations/001_add_season_id_to_leaderboard.up.sql`
- `migrations/001_add_season_id_to_leaderboard.down.sql`
- SQL Database Project: `db-project/Tables/leaderboard.sql` 반영(선언형 최종 상태)

## 프롬프트 예시 2 — inventory 소프트 삭제 컬럼 추가 (보조 예시)
> `inventory`에서 아이템을 물리 삭제하지 않고 소프트 삭제로 바꾸고 싶습니다.
> `is_deleted BIT`(기본 0)와 `deleted_at DATETIME2(3) NULL`을 추가하고, 활성 아이템만
> 빠르게 조회할 수 있는 필터드 인덱스를 넣어 주세요. `inventory`는 핫·대형 테이블이니
> 락을 최소화하는 방식으로요. 롤백도 같이요.

기대 산출물:
- `migrations/002_add_inventory_soft_delete.up.sql`
- `migrations/002_add_inventory_soft_delete.down.sql`
- SQL Database Project: `db-project/Tables/inventory.sql` 반영

## 하네스가 지켜야 하는 규칙 (프롬프트에 내장된 정책)
1. **Idempotent**: 재실행해도 안전(`IF NOT EXISTS`/`IF COL_LENGTH` 가드).
2. **온라인 우선**: 큰 테이블 인덱스는 `ONLINE = ON`(가능 에디션)·`RESUMABLE = ON`.
3. **비파괴 우선**: 컬럼 추가는 `NULL` 또는 `DEFAULT`로 시작(메타데이터 전용 변경 유도).
4. **롤백 대칭성**: 모든 up에는 되돌리는 down이 존재. down도 idempotent.
5. **미적용**: 스크립트는 생성만 하고 승인 전 배포 금지.
