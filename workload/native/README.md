# native — C++ MSOLEDBSQL 마이크로 드라이버 (선택/스트레치)

프로덕션 게임서버와 **동일한 클라이언트 스택**(C++ + MSOLEDBSQL / OLE DB)으로
핵심 핫패스인 **재화 이체** 한 가지를 재현합니다. 게임사 DBA 청중에게
"실제 게임서버가 붙는 방식 그대로"라는 신뢰를 주는 것이 목적입니다.

> **스트레치 산출물**: 스캐폴드 상태입니다. MSOLEDBSQL SDK(`msoledbsql.h`)가 필요하며
> 실제 Azure SQL MI에서 검증 후 데모에 사용하세요.

## 사전요건
- Visual Studio (C++ 워크로드) 또는 Build Tools + Windows SDK
- **Microsoft OLE DB Driver for SQL Server (MSOLEDBSQL)** 설치 (헤더/런타임)

## 빌드 (Developer Command Prompt / vcvars64)
```bat
cl /nologo /EHsc /std:c++17 currency_transfer.cpp ^
   /I "%MSOLEDBSQL_INCLUDE%" ole32.lib oleaut32.lib
```
> `msoledbsql.h`/`oledb.h` 경로가 SDK 위치에 따라 다를 수 있습니다. 필요 시 `/I`로 지정.

## 실행 (비밀 하드코딩 금지)
접속 문자열은 환경변수로만 전달합니다:
```powershell
$env:SQLMI_OLEDB_CONNSTR = "Provider=MSOLEDBSQL;Data Source=<mi-fqdn>,1433;Initial Catalog=gamedb;Authentication=ActiveDirectoryIntegrated;Encrypt=yes;"
.\currency_transfer.exe 1 2 10     # from=1 to=2 amount=10
```

## 데모 포인트
- OLE DB는 기본 `ARITHABORT OFF` 로 접속 → 프로덕션과 동일한 SET 옵션/플랜 캐시 동작.
- 낮은 `player_id` 를 먼저 잠가 정상 부하에서는 데드락을 피함(Python 드라이버와 동일 규칙).

## TODO (검증 시)
- 인라인 값 대신 OLE DB 파라미터 바인딩(`ICommandWithParameters`)으로 전환.
- 반복 실행/동시성 옵션 추가(현재는 단발성 스모크).
