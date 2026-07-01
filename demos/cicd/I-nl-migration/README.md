# I — 자연어 → 마이그레이션 + 롤백 자동 생성

DBA/개발자가 **자연어 한 줄**로 스키마 변경을 요청하면, AI 하네스가 이를 **idempotent
마이그레이션 + 대칭 롤백 스크립트**로 바꾸고, 동시에 **SQL Database Project(.sqlproj/DACPAC)**
선언형 최종 상태에도 반영하는 Database-as-Code 데모입니다. 기존 게임 스키마
(`players`/`inventory`/`currency_ledger`/`matches`/`leaderboard`) 기반.

## 구성
| 경로 | 내용 |
|------|------|
| `prompts/nl-request.md` | 자연어 요구 예시(주: leaderboard `season_id`+인덱스 / 보조: inventory 소프트삭제) + 하네스 규칙 |
| `migrations/001_*.up.sql` / `*.down.sql` | 시즌 정규화 키 추가 + 온라인 인덱스, 대칭 롤백 |
| `migrations/002_*.up.sql` / `*.down.sql` | inventory 소프트삭제 컬럼 + 필터드 인덱스, 대칭 롤백 |
| `db-project/` | 선언형 SQL Database Project(빌드 시 `GameDb.dacpac`) |

## 발표 흐름
1. `prompts/nl-request.md`의 자연어 요구를 그대로 하네스에 입력.
2. 하네스가 **명령형** 산출물(`migrations/001_*.up.sql` + `*.down.sql`)을 생성 — 멱등·온라인·비파괴.
3. 동시에 **선언형** 최종 상태(`db-project/Tables/leaderboard.sql` 등)에도 반영.
4. `db-project`를 빌드해 DACPAC 산출(데모 K 파이프라인의 입력물)까지 연결.
5. 변경은 **승인 전 미적용**. 롤백 스크립트가 함께 나오는 것을 강조.

## 기존 수동 방식 vs AI 하네스 방식
| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 요구 접수 | 요구를 티켓으로 받아 사람이 DDL로 번역 | 자연어 한 줄을 그대로 입력 |
| 마이그레이션 작성 | `ALTER`를 손으로 작성(멱등·온라인 옵션 누락 위험) | 멱등 가드 + `ONLINE/RESUMABLE` 포함해 자동 생성 |
| 롤백 | 사후에 급히 작성하거나 아예 누락 | up과 **대칭**인 down을 동시에 생성 |
| 최종 상태 관리 | 마이그레이션과 실제 스키마가 서서히 어긋남(drift) | 선언형 .sqlproj에 함께 반영 → DACPAC diff로 정합 |
| 대형 테이블 안전성 | "락 걸리려나" 경험에 의존 | 비파괴 추가(메타데이터 전용)·온라인 인덱스를 기본값으로 |

**발표 대본**
> (수동) "예전엔 요구사항을 제가 DDL로 옮기고, 온라인 옵션과 롤백은 종종 빠뜨렸습니다. 최종 스키마와 마이그레이션이 시간이 지나면 어긋나죠."
> (AI) "지금은 '`leaderboard`에 `season_id` 추가하고 인덱스도' 한 줄이면, 멱등·온라인 마이그레이션과 **대칭 롤백**이 같이 나오고, 선언형 SQL 프로젝트에도 반영돼 DACPAC 한 개로 정합이 유지됩니다. 승인 전엔 아무것도 적용되지 않습니다."

## 자연어 프롬프트 예시
> `leaderboard`에 `season_id`를 추가해 시즌별 랭킹을 분리하고, `season_id + rating DESC`
> Top-N 인덱스도 넣어 주세요. 운영 중 무중단으로 적용 가능해야 하고, 롤백 스크립트도
> 함께 만들어 주세요. **승인 전에는 배포하지 마세요.**

## Eval 기준
- `001_*.up.sql` → `001_*.down.sql` 순으로 실행해도 스키마가 원상복구(멱등).
- up 재실행 시 오류 없이 no-op(가드 동작).
- `db-project` 빌드 성공 → `GameDb.dacpac` 산출.
- 마이그레이션이 반영한 컬럼/인덱스가 `db-project` 선언형 정의와 일치(= 데모 K drift-check 통과).

## 안전/정책
- 실제 배포 없음(스크립트는 생성·검증까지). 비밀 하드코딩 금지.
- 대형 테이블 변경은 비파괴(메타데이터 전용)·`ONLINE=ON` 우선, 실패 시 오프라인 폴백.
