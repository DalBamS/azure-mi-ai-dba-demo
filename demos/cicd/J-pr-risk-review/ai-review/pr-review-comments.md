# 인라인 PR 리뷰 코멘트 (예시)

> 리뷰 에이전트가 GitHub PR의 **해당 라인에 직접** 남기는 코멘트 예시입니다.
> 각 코멘트는 [등급], 문제, 근거, **바로 적용 가능한 제안(suggestion 블록)** 순서로 작성됩니다.

---

### `sample-migrations/risky_alter_inventory.sql` L18–20
> 🔴 **[HIGH · 락/가용성] 대형 테이블 전체 백필**
> `inventory`는 핫·대형 테이블입니다. `NOT NULL` 컬럼 추가 뒤 전체 `UPDATE`는
> 대량 X락과 로그 폭증을 일으켜 재화/인벤 트랜잭션을 대기시킵니다. `last_seen_at`은
> 이미 `DEFAULT`가 있으므로 후속 `UPDATE`가 불필요합니다.
> ```suggestion
> ALTER TABLE dbo.inventory ADD last_seen_at DATETIME2(3) NOT NULL
>     CONSTRAINT DF_inventory_last_seen DEFAULT (SYSUTCDATETIME());
> -- 전체 UPDATE 제거: 신규 행은 DEFAULT, 기존 행은 배치로 별도 백필(필요 시).
> ```

### `sample-migrations/risky_alter_inventory.sql` L24
> 🔴 **[HIGH · 락/가용성] OFFLINE 인덱스 빌드**
> 온라인 옵션이 없어 인덱스 생성 동안 테이블이 잠깁니다.
> ```suggestion
> CREATE NONCLUSTERED INDEX IX_inventory_last_seen
>     ON dbo.inventory (last_seen_at)
>     WITH (ONLINE = ON, RESUMABLE = ON);
> ```

### `sample-migrations/risky_alter_inventory.sql` L29
> 🔴 **[HIGH · Breaking change] 컬럼 rename**
> `quantity → qty` rename은 배포 즉시 구버전 앱 쿼리를 깨뜨립니다. 무중단 배포가
> 불가하므로 expand-contract로 분리하세요: (1) `qty` 추가 + 동기화, (2) 앱 이행,
> (3) 다음 릴리스에서 `quantity` 제거. 이 PR에서는 rename을 제거해 주세요.

### `sample-migrations/risky_alter_inventory.sql` (파일 전체)
> 🔴 **[HIGH · 롤백] down 스크립트 부재**
> 대응하는 `.down.sql`이 없습니다. 인덱스 drop → 컬럼 drop 순의 멱등 롤백을 추가해 주세요.

---

### `sample-migrations/risky_drop_column.sql` L11
> 🔴 **[HIGH · 데이터 손실] DROP COLUMN**
> `updated_at`은 감사/디버깅에 사용됩니다. 삭제는 되돌릴 수 없습니다. 정말 필요하면
> 보존 정책을 확인하고, DACPAC 배포에서 `BlockOnPossibleDataLoss=true`(기본값)로
> 파괴적 변경을 게이트하세요.

### `sample-migrations/risky_drop_column.sql` L16–25
> 🔴 **[CRITICAL · 데이터 손실] DROP TABLE 후 재생성**
> 랭킹 데이터가 전량 소실되고 `wins/losses/rank_pos/updated_at`이 사라져 breaking
> change까지 겹칩니다. in-place `ALTER`로 필요한 변경만 적용하세요.

### `sample-migrations/risky_drop_column.sql` L28
> 🔴 **[CRITICAL · 데이터 손실] TRUNCATE**
> 매치 이력은 복구 불가입니다. 마이그레이션에서 데이터 삭제를 제거하고, 정리가
> 필요하면 별도 승인 워크플로로 분리하세요.

---

**리뷰 종합 코멘트(자동)**
> 이 PR은 🔴 위험을 포함해 **Request changes**로 표시했습니다. 위 suggestion을 적용하면
> 락/가용성·롤백 지적은 해소됩니다. rename/데이터 손실 항목은 배포 전략 변경이 필요합니다.
