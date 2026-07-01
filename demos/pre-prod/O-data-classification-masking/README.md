# O — [보안 플래그십] 민감정보 자동분류 + 마스킹/RLS 정책 생성

게임 서비스의 **개인정보(닉네임·이메일·결제)** 컬럼을 AI가 자동 발견·분류하고, **DDM(동적 데이터 마스킹)** 과 **RLS(행 수준 보안)** 정책 초안을 생성한 뒤 승인·적용까지 하네스로 잇습니다. 배포 전 개인정보 보호 게이트로 활용합니다.

> **프레임**: 격리/데모 환경. 합성 데이터만 사용(실 PII·실 카드번호 없음). "AI 방어" 관점 — 공격이 아니라 **보호 정책 자동화**.

## 구성 파일
| 파일 | 역할 |
|------|------|
| `00_optional_payment_table.sql` | (선택) 결제 PII 예시 `dbo.payment_methods` 데모 테이블. 기본 미적용 |
| `01_classify.sql` | (읽기전용) PII 후보 발견 → `ADD SENSITIVITY CLASSIFICATION` 태깅 |
| `02_recommend_policies.sql` | 분류 근거로 DDM/RLS T-SQL **초안 생성(미적용)** |
| `03_apply_masking_rls.sql` | 승인 후 DDM(email/username) + region 기반 RLS 적용 |
| `04_eval.sql` | 분류·마스킹·RLS 적용 여부 및 RLS 동작 검증 |
| `05_rollback.sql` | 정책/함수/마스크/분류/선택 테이블 원복 |

## 발표 흐름
1. (선택) `00_optional_payment_table.sql`로 결제 PII 데모 테이블 생성.
2. `01_classify.sql` PART A로 컬럼명/타입 패턴에서 PII 후보를 발견(읽기전용) → PART B로 `players.email/username/region` 태깅.
3. `02_recommend_policies.sql`로 DDM/RLS **초안 스크립트**를 출력 — AI가 제안, 사람이 검토.
4. 승인 후 `03_apply_masking_rls.sql`로 email 마스킹·username 부분마스킹·region RLS 적용.
5. `04_eval.sql`로 `sys.masked_columns`/`sys.security_policies`/`sys.sensitivity_classifications` 검증 + RLS 행 필터 동작 확인.
6. 데모 후 `05_rollback.sql`로 전량 원복.

## 안전 설계 포인트
- **RLS 안전 술어**: `SESSION_CONTEXT('region')`가 없으면(서비스/관리 세션) 전체 허용, 설정된 경우에만 해당 region 행으로 제한 → **부하 드라이버/타 데모에 무영향**. `db_owner` 예외 포함.
- **DDM**은 `UNMASK` 권한 없는 사용자에게만 가려짐 — 관리자/서비스 계정 조회는 그대로.
- 모든 생성물은 `05_rollback.sql`로 정리(운영팩 일관성).

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA/보안 수동 방식 | AI 하네스 방식 |
|------|------------------------|----------------|
| PII 식별 | 스키마를 사람이 훑어 민감 컬럼 추정 | 이름/타입 패턴으로 후보 자동 발견 + 라벨 제안 |
| 분류 태깅 | 수작업, 누락·비일관 | `ADD SENSITIVITY CLASSIFICATION` 일괄 태깅 |
| 정책 작성 | DDM/RLS T-SQL을 처음부터 손으로 | 분류 근거로 정책 **초안 자동 생성** |
| 검토/적용 | 검토와 적용이 뒤섞임 | 제안(02) → 승인 → 적용(03) 분리, 사람이 게이트 |
| 검증 | "적용됐겠지" | `sys.*` 카탈로그로 적용·동작 정량 검증 |
| 원복 | 잔존 정책 위험 | 대응 `05_rollback.sql` 제공 |

**발표 대본**
> (수동) "개인정보 컬럼이 뭔지 스키마 보고 사람이 추립니다. 마스킹이랑 RLS는 T-SQL을 처음부터 손으로 짜야 하고, 빠뜨리면 그대로 유출 리스크가 됩니다. 배포 전에 이걸 매번 하긴 어렵죠."
> (AI) "하네스가 컬럼 패턴에서 PII 후보를 찾아 라벨을 제안하고, 분류를 근거로 DDM/RLS 초안을 만들어 줍니다. 사람은 초안을 검토·승인만 하면 됩니다. RLS 술어는 서비스 세션엔 영향이 없게 안전하게 설계했고, 적용 결과는 카탈로그 뷰로 검증합니다. 전부 롤백 스크립트로 되돌릴 수 있어 배포 전 개인정보 게이트로 반복 적용할 수 있습니다."

## Eval 기준
- `04_eval.sql`: 분류 3건 이상, `players.email/username` 마스크 존재, `Security.rls_players` 정책이 STATE=ON.
- RLS 동작: 컨텍스트 미설정 = 전체 행, region 설정 = 축소, 리셋 = 복원 → `PASS`.

## 정리(cleanup)
- `05_rollback.sql`로 정책·함수·스키마·마스크·분류·선택 테이블 전량 원복.
