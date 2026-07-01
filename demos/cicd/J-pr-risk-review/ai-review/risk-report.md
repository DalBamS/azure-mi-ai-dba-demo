# AI 위험 진단 리포트 (예시 출력)

> 리뷰 에이전트가 `sample-migrations/`의 두 PR을 분석해 생성한 리포트 예시입니다.
> 실제 데모에서는 하네스가 PR diff를 입력받아 이 형식으로 자동 생성합니다.

---

## PR #101 — "inventory에 last_seen_at 추가 + 인덱스"
**대상 파일**: `sample-migrations/risky_alter_inventory.sql`
**종합 위험도: 🔴 HIGH — 머지 차단(block) 권고**

| # | 위험 | 카테고리 | 등급 | 근거 | 완화책 |
|---|------|----------|------|------|--------|
| 1 | `inventory`(핫·대형)에 `NOT NULL` 컬럼 추가 후 전체 `UPDATE` 백필 | 락/가용성 | 🔴 | 전체 행 갱신 → 대량 X락·로그 폭증, 재화/인벤 트랜잭션 대기 | 상수 DEFAULT로 추가(메타데이터 전용) 후 배치 백필. `last_seen_at`은 이미 DEFAULT가 있으므로 후속 `UPDATE` 불필요 |
| 2 | `CREATE INDEX`에 `ONLINE = ON` 누락 | 락/가용성 | 🔴 | 인덱스 빌드 동안 테이블 Sch-M 잠금 → 워크로드 차단 | `WITH (ONLINE = ON, RESUMABLE = ON)` |
| 3 | `sp_rename ... quantity → qty` | Breaking change | 🔴 | 구버전 앱의 `quantity` 참조 쿼리가 배포 즉시 실패 | expand-contract: 새 컬럼 추가→앱 이행→구 컬럼 제거 |
| 4 | 롤백 스크립트 없음 | 롤백 안전성 | 🔴 | 문제 발생 시 되돌릴 대칭 down 부재 | `.down.sql` 추가(인덱스 drop→컬럼 drop→rename 원복) |

**머지 게이트**: 🔴 4건 → **block**. #3(rename)은 무중단 배포 자체가 불가하므로 설계 변경 필요.

---

## PR #102 — "leaderboard 스키마 정리"
**대상 파일**: `sample-migrations/risky_drop_column.sql`
**종합 위험도: 🔴 CRITICAL — 머지 차단(block) 권고**

| # | 위험 | 카테고리 | 등급 | 근거 | 완화책 |
|---|------|----------|------|------|--------|
| 1 | `currency_ledger DROP COLUMN updated_at` | 데이터 손실 | 🔴 | 되돌릴 수 없는 컬럼 삭제(감사 정보 소실) | 보존 필요성 확인, DACPAC `BlockOnPossibleDataLoss=true`로 차단 |
| 2 | `DROP TABLE leaderboard` 후 재생성 | 데이터 손실 | 🔴 | 랭킹 데이터 전량 소실 + `wins/losses/rank_pos/updated_at` 사라짐(breaking) | in-place `ALTER`로 대체 |
| 3 | `TRUNCATE TABLE matches` | 데이터 손실 | 🔴 | 매치 이력 복구 불가 | 마이그레이션에서 제거, 데이터 정리는 별도 승인 절차 |

**머지 게이트**: 🔴 3건(데이터 손실) → **block**. 프로덕션 데이터 파괴 위험으로 즉시 반려.

---

## 요약 (발표용 한 장)
- 사람 리뷰어가 놓치기 쉬운 **온라인성·롤백 대칭성·breaking**을 규칙 기반으로 일관 검출.
- 각 지적에 **근거 + 완화 코드**를 함께 제시 → 리뷰가 "지적"이 아니라 "수정 가이드"가 됨.
- 🔴 존재 시 자동 **block**으로 위험 머지를 게이트.
