# J — PR 리뷰 에이전트가 마이그레이션 위험 진단 (킬러 데모)

스키마 변경 PR이 올라오면 AI 하네스가 **위험을 자동 진단**한다: 대형 테이블(`inventory`)
ALTER 락, 비온라인 인덱스, breaking change, 데이터 손실(컬럼/테이블 삭제), 롤백 안전성.
여기에 **보안 게이트**(과잉 GRANT 최소권한 제안 · 시크릿 스캔 · 마스킹 누락 검출)를 더해
위험한 머지를 막는다. 사람이 놓치기 쉬운 것을 규칙 기반으로 일관되게 잡는 것이 핵심.

## 구성
| 경로 | 내용 |
|------|------|
| `sample-migrations/risky_alter_inventory.sql` | 락·비온라인·rename·롤백부재를 일부러 담은 위험 PR |
| `sample-migrations/risky_drop_column.sql` | DROP COLUMN/DROP TABLE/TRUNCATE 데이터 손실 PR |
| `ai-review/risk-rubric.md` | 에이전트가 따르는 위험 판정 루브릭(카테고리·등급·완화) |
| `ai-review/risk-report.md` | 위 두 PR에 대한 위험 진단 리포트 예시 |
| `ai-review/pr-review-comments.md` | 해당 라인에 남기는 인라인 코멘트(+suggestion) 예시 |
| `security-gate/over-privilege.sql` | 과잉 GRANT vs 최소권한 제안 |
| `security-gate/masking-gap.sql` | 민감 컬럼 DDM 누락 검출 + 마스킹 제안 |
| `security-gate/secret-scan.md` | 시크릿 스캔 규칙·예시(가짜)·대체안 |

## 발표 흐름
1. `sample-migrations/`의 위험 PR을 리뷰 대상으로 제시.
2. 하네스가 `ai-review/risk-rubric.md` 기준으로 diff를 스캔.
3. `ai-review/risk-report.md`(종합 위험 등급) + `pr-review-comments.md`(라인별 suggestion) 생성.
4. 보안 게이트가 과잉 권한·마스킹 누락·시크릿을 추가로 지적(`security-gate/`).
5. 🔴가 하나라도 있으면 **머지 차단(block)** — 완화책과 함께 반려.

## 기존 수동 방식 vs AI 하네스 방식
| 단계 | 기존 DBA/리뷰어 수동 방식 | AI 하네스 방식 |
|------|--------------------------|----------------|
| 위험 인지 | 리뷰어 경험·기억에 의존, 사람마다 편차 | 루브릭 기반으로 락/온라인성/breaking/손실/롤백을 일관 검출 |
| 대형 테이블 락 | "이거 큰 테이블인데…" 감으로 지적 | 저장소 기준 대형 테이블 목록으로 명시 판정 |
| Breaking change | 배포 후에야 앱 오류로 발견 | rename/타입축소를 사전 차단, expand-contract 제안 |
| 데이터 손실 | DROP/TRUNCATE를 놓치면 사고 | 손실 구문을 🔴로 즉시 게이트 |
| 보안 | GRANT/시크릿/마스킹은 별도 검토(자주 누락) | 최소권한·시크릿·DDM을 리뷰에 통합 |
| 산출물 | "고쳐오세요" 지적만 | 근거 + **바로 적용 가능한 suggestion 코드** |

**발표 대본**
> (수동) "리뷰어 세 명이면 지적도 세 갈래입니다. 큰 테이블 락은 누가 잡고, 롤백 누락은 놓치고, GRANT 과잉은 아무도 안 봅니다. breaking change는 배포하고 나서야 압니다."
> (AI) "지금은 같은 루브릭으로 매 PR을 스캔합니다. `inventory` ALTER의 온라인 옵션 누락, `quantity` rename의 breaking, `DROP TABLE`의 데이터 손실, 과잉 `GRANT`, 마스킹 누락, 하드코딩 시크릿까지 한 번에 잡고, 각 지적에 **수정 코드**를 붙여 돌려줍니다. 🔴가 있으면 머지를 막습니다."

## 자연어 프롬프트 예시
> 이 PR의 마이그레이션을 리뷰해 주세요. 대형 테이블 락, 비온라인 인덱스, breaking
> change, 데이터 손실, 롤백 안전성을 확인하고, 과잉 권한·마스킹 누락·하드코딩 시크릿 같은
> 보안 문제도 함께 봐 주세요. 위험마다 등급과 **수정 제안 코드**를 붙이고, 위험하면 머지를
> 막아 주세요.

## Eval 기준
- 두 위험 PR에서 🔴 위험이 **누락 없이** 검출(락·비온라인·rename·DROP/TRUNCATE·롤백부재).
- 각 지적에 근거 + 완화(suggestion)가 포함.
- 보안 게이트가 과잉 GRANT(CONTROL/db_owner/public)·마스킹 누락·시크릿 후보를 지적.
- 종합 판정이 **block**(🔴 존재 시)으로 산출.

## 안전/정책
- 위험 샘플은 **실행 목적이 아님**(리뷰 입력). 시크릿 예시는 전부 가짜(placeholder).
- 최소권한·마스킹·시크릿 제거를 기본 권고로 삼음(저장소 보안 컨벤션과 정렬).
