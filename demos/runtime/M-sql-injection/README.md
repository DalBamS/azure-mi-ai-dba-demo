# M — SQL Injection 탐지 · 진단

격리된 데모 MI에서 취약한 동적 SQL 저장 프로시저를 만들고, AI가 audit/쿼리 텍스트/Defender 스타일 근거로 injection 시도를 진단한 뒤 파라미터화된 안전한 구현을 제안하는 보안 운영 데모입니다.

## 연결 이슈
- 유발: `issue-injection\06_sql_injection.sql`
- 롤백: `issue-injection\06_sql_injection.rollback.sql`
- 주의: **격리된 데모 MI에서만 실행**. 프로덕션 금지.

## 발표 흐름
1. `issue-injection\06_sql_injection.sql`로 취약 proc 생성.
2. `01_reproduce.sql`로 benign 호출과 injection 패턴 호출을 실행.
3. `02_diagnose.sql`로 최근 쿼리 텍스트, 취약 proc 정의, audit/Defender 연결 포인트 확인.
4. AI가 문자열 연결 기반 dynamic SQL과 `OR 1=1 --`, metadata reconnaissance 패턴을 설명.
5. `03_eval.sql`로 취약 proc 존재/패턴 감지.
6. 승인 후 `04_remediate.sql`로 안전한 proc 예시 생성.
7. `05_rollback.sql`로 취약 proc/예시 proc 정리.

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 인지 | Defender/Audit 경보를 사람이 콘솔에서 확인 | "SQLi 의심 알림이 떴다" 자연어로 접수 |
| 증거 수집 | audit 로그·쿼리 텍스트를 손으로 검색 | `02_diagnose.sql`로 취약 proc 정의·의심 쿼리·audit 연결점 수집 |
| 원인 판단 | 취약 코드 위치를 눈으로 추적 | 문자열 연결 dynamic SQL + `OR 1=1 --`·메타데이터 정찰 패턴을 설명 |
| 수정안 | 파라미터화 필요성은 알지만 우선순위에서 밀림 | `04_remediate.sql`의 파라미터화 안전 proc를 승인용으로 즉시 제시 |
| 검증(Eval) | 수정 여부를 사람이 재확인 | `03_eval.sql`로 `EXEC(@sql)`+concatenation 취약 패턴 제거를 검증 |
| 자세 | 사고 대응이 사후·수동적 | "AI 방어" — 탐지·근본원인·수정안을 한 흐름으로 |

> ⚠ **안전 원칙**: 이 데모는 **격리된 데모 MI 한정**이며, 취약 재현은 방어를 보여주기 위한 것입니다. 공유 인프라나 프로덕션을 대상으로 한 실제 공격은 금지합니다. 프레임은 "공격 시연"이 아니라 **"AI가 어떻게 탐지·진단·차단을 돕는가"** 입니다.

**발표 대본**
> (수동) "SQL Injection 경보는 뜨는데, 정작 어느 proc의 어떤 입력이 문제인지 찾는 건 audit 로그를 손으로 뒤지는 지루한 작업이었습니다. 근본 원인까지 가려면 코드도 따로 열어야 했죠."
> (AI) "하네스는 취약 proc 정의와 injection 시도 흔적을 함께 모아 '문자열을 이어붙인 dynamic SQL이 원인'임을 짚고, 파라미터화된 안전한 구현을 승인용으로 제안합니다. 어디까지나 격리 환경에서 '방어'를 보여주는 것이고, 공유 인프라에 실공격은 하지 않습니다."

## 자연어 프롬프트 예시
> Defender for SQL에서 SQL Injection 의심 알림이 발생했습니다. 어떤 저장 프로시저와 입력 패턴이 의심스러운지 확인하고, 취약 코드의 원인과 안전한 수정안을 제안해 주세요. 격리 데모 환경이라는 전제에서만 재현해 주세요.

## Eval 기준
- 취약 proc 정의에 `EXEC(@sql)`와 input concatenation이 확인됨.
- injection-like cached statement 또는 audit evidence를 제시.
- remediation은 동적 SQL 없이 파라미터화된 정적 쿼리 사용.
