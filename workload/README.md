# /workload — 상시 부하 (계층형)

실제 운영처럼 트랜잭션이 흐르도록 3계층으로 부하를 구성합니다.

## 1. /hammerdb — 베이스라인 OLTP
HammerDB **TPROC-C**로 상시 베이스라인 OLTP 부하를 만듭니다. (셋업 가이드 + config)

## 2. /game-driver — 게임 트랜잭션 믹스 (Python, pyodbc)
게임 특화 트랜잭션을 흉내내는 커스텀 드라이버:
- **재화 이체** (currency_ledger 교차 UPDATE → blocking/deadlock 지점)
- **인벤 업데이트** (inventory 핫 테이블)
- **랭킹 조회** (leaderboard)

프로덕션은 **C++ / MSOLEDBSQL(OLE DB)** 이므로, 드라이버가 실제로 영향을 주는 부분
(SET 옵션)을 프로덕션에 맞춥니다: `MIMIC_OLEDB_SET_OPTIONS=true` 시 연결 직후
`SET ARITHABORT OFF` 등 OLE DB 기본값을 적용 → "SSMS에선 빠른데 앱에선 느린"
Plan regression 데모가 진짜처럼 재현됩니다.

## 3. /native — (선택/스트레치) C++ MSOLEDBSQL 마이크로 드라이버
핫패스 1개(재화 이체)만 프로덕션과 **동일한 연결 방식**으로 구현하여
게임사 DBA 청중에게 "실제 게임서버가 붙는 방식 그대로"라는 신뢰를 제공합니다.
