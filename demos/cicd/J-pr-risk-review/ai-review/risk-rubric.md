# PR 위험 판정 루브릭 (AI 하네스가 따르는 기준)

리뷰 에이전트는 스키마 변경 PR의 각 문장을 아래 카테고리로 스캔하고, **위험도(🔴 높음 /
🟠 중간 / 🟢 낮음)** 와 **근거·완화책**을 붙인다. 대형 테이블 목록은 저장소 기준
(`inventory`, `matches`, `currency_ledger`가 핫/대형)으로 판단한다.

## 1. 락 & 가용성 (온라인성)
| 신호 | 위험 | 완화 |
|------|------|------|
| 대형 테이블 `ALTER`/`CREATE INDEX` 에 `ONLINE = ON` 없음 | 🔴 | `WITH (ONLINE = ON, RESUMABLE = ON)` |
| `NOT NULL` 컬럼을 상수 DEFAULT 없이 추가 + 백필 | 🔴 | 상수 DEFAULT 로 추가(메타데이터 전용) 후 배치 백필 |
| 전체 테이블 `UPDATE`/`DELETE` 단일 트랜잭션 | 🟠 | 배치 처리(예: 5k행 루프) |

## 2. Breaking change (하위호환)
| 신호 | 위험 | 완화 |
|------|------|------|
| 컬럼/테이블 `rename` | 🔴 | expand-contract: 새 컬럼 추가→앱 이행→구 컬럼 제거 |
| 컬럼 삭제/타입 축소 | 🔴 | 3단계 배포로 분리, 앱 버전 게이팅 |
| NOT NULL 로 제약 강화(기존 NULL 존재) | 🟠 | 백필 후 `WITH CHECK` |

## 3. 데이터 손실
| 신호 | 위험 | 완화 |
|------|------|------|
| `DROP COLUMN` / `DROP TABLE` / `TRUNCATE` | 🔴 | 백업/보존 확인, DACPAC `BlockOnPossibleDataLoss=true` |
| drop-then-create 로 테이블 재생성 | 🔴 | in-place `ALTER` 로 대체 |

## 4. 롤백 안전성
| 신호 | 위험 | 완화 |
|------|------|------|
| 대응 down 스크립트 없음 | 🔴 | 모든 up 에 대칭 down 요구 |
| down 이 비멱등 | 🟠 | `IF EXISTS`/`IF COL_LENGTH` 가드 |

## 5. 보안 게이트
| 신호 | 위험 | 완화 |
|------|------|------|
| 과잉 권한(`GRANT CONTROL`/`db_owner`/`GRANT ... TO public`) | 🔴 | 최소권한(대상 객체 한정 GRANT) |
| 하드코딩된 시크릿/커넥션스트링/`CREATE LOGIN ... PASSWORD` | 🔴 | secrets/Key Vault/OIDC 로 이동 |
| 신규 민감 컬럼에 마스킹(DDM) 누락 | 🟠 | `MASKED WITH (...)` + 분류 라벨 |

## 판정 출력 형식
에이전트는 (1) 요약 위험 등급, (2) 라인별 인라인 코멘트, (3) 머지 게이트 권고
(block / request-changes / approve-with-nits)를 생성한다. 🔴 가 하나라도 있으면 기본 **block**.
