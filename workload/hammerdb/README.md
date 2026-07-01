# HammerDB TPROC-C — 베이스라인 OLTP 부하

HammerDB의 **TPROC-C**(TPC-C 계열 OLTP) 워크로드로 Azure SQL MI에 상시 베이스라인
부하를 겁니다. 게임 특화 트래픽은 `..\game-driver`(Python)가 담당하고, HammerDB는
"항상 뭔가 돌고 있는" 기본 OLTP 배경 부하를 제공합니다.

> HammerDB의 TPROC-C 스키마는 게임 스키마(`/schema`)와 **별개 DB**에 둡니다.
> 두 부하를 동일 인스턴스에서 병렬로 돌려 현실적인 혼합 부하를 만듭니다.

## 사전요건
- [HammerDB](https://www.hammerdb.com/) 4.x 이상 (Windows GUI 또는 CLI `hammerdbcli`)
- **ODBC Driver 18 for SQL Server**
- 접속 정보는 `.env`/환경변수에서만. 스크립트에 비밀 하드코딩 금지.

## 1) 스키마 빌드 (CLI 예시)
`build_tproc.tcl` (예시 — 값은 환경에 맞게, 비밀은 환경변수로 주입):
```tcl
dbset db mssqls
diset connection mssqls_server $env(SQLMI_SERVER)
diset connection mssqls_port   $env(SQLMI_PORT)
diset connection mssqls_encrypt_connection true
diset connection mssqls_authentication windows   ;# 또는 azureactivedirectory
diset tpcc mssqls_dbase tpcc
diset tpcc mssqls_count_ware 20                    ;# 창고 수 = 규모 파라미터
diset tpcc mssqls_num_vu 8
buildschema
```
실행:
```powershell
hammerdbcli auto build_tproc.tcl
```

## 2) 상시 부하 구동
`run_tproc.tcl` (예시):
```tcl
dbset db mssqls
diset connection mssqls_server $env(SQLMI_SERVER)
diset tpcc mssqls_dbase tpcc
diset tpcc mssqls_driver timed
diset tpcc mssqls_rampup 2
diset tpcc mssqls_duration 60      ;# 분; 데모 중엔 길게 또는 반복
vuset vu 8
loadscript
vucreate
vurun
```
```powershell
hammerdbcli auto run_tproc.tcl
```

## 인증 노트
- 가능하면 **Entra ID(AAD)** 인증 사용. HammerDB의 `mssqls_authentication`을
  `azureactivedirectory` 로 설정하고 토큰/자격 증명은 OS/az CLI 컨텍스트에서 해석.
- SQL 인증은 로컬/개발 한정. 비밀번호는 Key Vault/환경변수로만.

## 데모에서의 역할
- 상시 OLTP 배경 부하 → CPU/IO/로그 활동이 항상 존재 → 운영 데모(A/B/C)의 현실감.
- 게임 특화 이슈(랭킹 풀스캔, 재화·인벤 데드락 등)는 `game-driver` + `issue-injection`이 담당.
