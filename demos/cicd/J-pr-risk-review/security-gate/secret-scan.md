# 보안 게이트: 시크릿 스캔 (마이그레이션/PR 대상)

PR 리뷰 에이전트는 스키마 변경 diff에서 **하드코딩된 시크릿·커넥션스트링·평문 자격증명**을
탐지해 🔴로 게이트한다. 이 문서는 탐지 규칙과 (가짜) 예시, 대체안을 담는다.

> ⚠ 아래 예시는 **전부 가짜(placeholder)** 값입니다. 실제 시크릿이 아닙니다.

## 탐지 규칙 (정규식/휴리스틱)
| 규칙 | 패턴(요지) | 예시(가짜) |
|------|-----------|-----------|
| SQL 로그인 평문 비밀번호 | `CREATE\|ALTER LOGIN ... PASSWORD = '...'` | `CREATE LOGIN app WITH PASSWORD = 'P@ssw0rd-EXAMPLE';` |
| ADO.NET 커넥션스트링 | `Server=...;Password=...;` | `Server=tcp:mi.example;User ID=sa;Password=Fake_123;` |
| 계정 키/토큰 | `AccountKey=`, `SharedAccessSignature=`, `xoxb-`, `ghp_` | `AccountKey=AAAAfakebase64==;` |
| 자격증명 SECRET | `CREATE ... CREDENTIAL ... SECRET = '...'` | `WITH IDENTITY='x', SECRET='fake-sas';` |
| 사설키 블록 | `-----BEGIN (RSA )?PRIVATE KEY-----` | (키 블록) |

## ❌ 나쁜 예 (탐지되어야 함)
```sql
-- 마이그레이션에 로그인+평문 비번을 박아넣음 → 🔴 block
CREATE LOGIN etl_user WITH PASSWORD = 'Sup3rSecret-EXAMPLE!';
GO
-- 외부 데이터 소스에 SAS 시크릿 하드코딩 → 🔴 block
CREATE DATABASE SCOPED CREDENTIAL cred_blob
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
         SECRET = 'sv=2022-11-02&ss=b&sig=FAKEFAKEFAKE';   -- 가짜
GO
```

## ✅ 제안 (대체안)
- **비밀은 코드/마이그레이션에 두지 않는다.** GitHub Actions는 `secrets` + **OIDC(`azure/login`)**로
  런타임에 주입, 앱/드라이버는 **Azure Key Vault** 또는 관리형 ID로 해결(저장소 컨벤션과 동일).
- 로그인 생성이 꼭 필요하면 비밀번호를 파이프라인 시크릿에서 `sqlcmd -v` 변수로 주입:
  ```sql
  CREATE LOGIN etl_user WITH PASSWORD = '$(ETL_PASSWORD)';  -- 값은 CI 시크릿에서
  ```
- 자격증명은 관리형 ID/Key Vault 참조로 대체하고, 저장소에는 **참조 이름만** 남긴다.

## 게이트 동작
- 시크릿 후보 1건이라도 발견 → PR 상태 **block**, 라인 인라인 코멘트로 대체안 제시.
- 오탐 방지: 명백한 placeholder(`EXAMPLE`, `FAKE`, `$(...)` 변수)는 경고(🟠)로 완화.
- CI에서는 `gitleaks`/`detect-secrets` 같은 표준 스캐너와 병행(데모 K 워크플로에 훅 지점 표시).
