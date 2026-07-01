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

## 자연어 프롬프트 예시
> Defender for SQL에서 SQL Injection 의심 알림이 발생했습니다. 어떤 저장 프로시저와 입력 패턴이 의심스러운지 확인하고, 취약 코드의 원인과 안전한 수정안을 제안해 주세요. 격리 데모 환경이라는 전제에서만 재현해 주세요.

## Eval 기준
- 취약 proc 정의에 `EXEC(@sql)`와 input concatenation이 확인됨.
- injection-like cached statement 또는 audit evidence를 제시.
- remediation은 동적 SQL 없이 파라미터화된 정적 쿼리 사용.
