# game-driver — Python 게임 부하 드라이버

게임 특화 트랜잭션 믹스(재화 이체 / 인벤 업데이트 / 랭킹 조회)를 동시 실행하여
데모 환경에 **상시 트래픽**을 흘려보냅니다. HammerDB TPROC-C 베이스라인 위에 얹어
게임 워크로드 색깔을 입히고, 이슈 주입 시나리오의 배경 부하가 됩니다.

## 프로덕션 진정성: OLE DB SET 옵션 흉내
프로덕션 게임서버는 **C++ / MSOLEDBSQL(OLE DB)** 로 연결합니다. OLE DB 앱은 기본적으로
`ARITHABORT OFF` 로 접속하는데, SSMS는 `ARITHABORT ON` 입니다. SET 옵션이 다르면
**플랜 캐시 항목이 분리**되어 "SSMS에선 빠른데 앱에선 느린" Plan regression의 전형적
원인이 됩니다. `MIMIC_OLEDB_SET_OPTIONS=true`(기본) 이면 연결 직후 OLE DB 기본 SET
옵션을 적용해, 운영(C: Plan regression) 데모가 진짜처럼 재현됩니다. (`db.py` 참고)

## 사전요건
- Python 3.10+
- **ODBC Driver 18 for SQL Server** 설치
- 리포지토리 루트 `.env` 구성 (루트 `.env.example` 복사). 비밀 하드코딩 금지.

## 설치 & 실행
```powershell
cd workload\game-driver
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

python driver.py                 # Ctrl+C 까지 (또는 WORKLOAD_DURATION_SECONDS)
python driver.py --duration 120  # 120초
python driver.py --concurrency 16
```

## 설정 (환경변수)
| 변수 | 의미 | 기본 |
|------|------|------|
| `AUTH_MODE` | `aad-integrated` / `aad-service-principal` / `aad-password` / `sql` | aad-integrated |
| `MIMIC_OLEDB_SET_OPTIONS` | OLE DB 기본 SET 옵션 흉내 | true |
| `WORKLOAD_CONCURRENCY` | 워커 스레드 수 | 8 |
| `WORKLOAD_DURATION_SECONDS` | 실행 시간(0=무한) | 0 |
| `WORKLOAD_MIX_CURRENCY_TRANSFER` / `_INVENTORY_UPDATE` / `_RANKING_QUERY` | 믹스 비율 | 40/40/20 |

인증/접속 변수(`SQLMI_SERVER` 등)는 루트 `.env.example` 참고.

## 파일
- `config.py` — 환경변수/Key Vault 기반 설정 로딩(비밀 하드코딩 금지).
- `db.py` — AUTH_MODE별 pyodbc 연결 + OLE DB SET 옵션 적용.
- `transactions.py` — 재화 이체 / 인벤 업데이트 / 랭킹 조회 (전부 파라미터화).
- `driver.py` — 동시 워커 + 가중 믹스 + 처리량/데드락 리포팅.

## 참고
- 정상 부하는 재화 이체 시 **오름차순 player_id 락 순서**를 지켜 데드락을 피합니다.
  데드락은 issue-injection #2 가 **상반된 락 순서** 변형으로 의도적으로 유발합니다.
- SQL Injection 데모(M/#6)는 여기서 재현하지 않습니다 — issue-injection에 격리.
