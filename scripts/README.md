# /scripts — 헬퍼 스크립트

환경 구성 실행을 돕는 PowerShell 스크립트. 접속 정보는 **오직 `.env`/환경변수/Key Vault**
에서 읽습니다. 하드코딩 금지. (PowerShell 7+ 권장)

| 스크립트 | 역할 |
|----------|------|
| `lib.ps1` | 공용 함수: `.env` 로딩, Key Vault 비밀 조회, AUTH_MODE별 sqlcmd 인자 생성 |
| `check-prereqs.ps1` | 사전요건 점검 (sqlcmd, python, az, ODBC Driver 18, `.env`) |
| `apply-schema.ps1` | 게임 스키마 DDL + 인덱스 적용 (idempotent) |
| `seed.ps1` | 시드 데이터 생성 (`-Profile default\|smoke`, `-Reset`, 규모 파라미터) |

## 인증 (AUTH_MODE)
`lib.ps1`의 `Get-SqlcmdArgs`가 `AUTH_MODE`에 따라 sqlcmd 인자를 구성합니다:
- `aad-integrated` → `-G`
- `aad-password` → `-G -U -P`
- `sql` → `-U -P` (비밀은 Key Vault 우선)

## 예시
```powershell
.\check-prereqs.ps1
.\apply-schema.ps1
.\seed.ps1 -Profile smoke        # 로컬 스모크
.\seed.ps1 -Reset                # 초기화 후 재시드(default 규모)
```

## 원칙
- 모든 파괴적 작업(이슈 주입, `-Reset` 등)은 명시적 플래그 요구.
