# F — 워크로드 리플레이 가이드 (02)

캡처(`01_capture.sql`)한 워크로드를 **다른 티어/버전**에 재생(replay)해 회귀를 검증합니다. 목적은 "버전 업그레이드/티어 변경 후 같은 부하에서 느려지는 게 있는가?"를 데이터로 답하는 것입니다.

## 리플레이 옵션

### A. game-driver 재실행 (가장 간단, 권장 데모)
동일한 부하 프로파일을 대상 환경에 그대로 실행합니다. E 데모의 프로파일을 재사용하면 baseline과 replay가 **동일 믹스/동접**임을 보장할 수 있습니다.
```powershell
# baseline 환경 .env로 실행 (기준 구간)
python workload\game-driver\driver.py --duration 300
# ... 대상(업그레이드/다른 티어) 환경 .env로 동일하게 실행 (리플레이 구간)
python workload\game-driver\driver.py --duration 300
```
- 두 구간의 **시작/종료 UTC 시각**을 기록해 두세요. `03_compare_waits.sql`에 넣습니다.

### B. ostress / RML Utilities (문장 단위 충실 재생)
`01_capture.sql`의 XEvents 스트림(또는 별도 파일 타깃)을 추출해 ostress로 재생합니다.
```powershell
# 예시 — 캡처에서 추출한 배치 스크립트를 N회/동시성으로 재생
ostress.exe -S <server> -d <gamedb> -E -i capture_batches.sql -n 8 -r 100
```
- 접속/인증은 환경변수·통합인증으로만. **비밀 하드코딩 금지.**
- RML/ostress는 별도 설치물이며 실제 프로비저닝은 하지 않습니다(가이드만 제공).

### C. Distributed Replay (참고)
대규모 충실 재생이 필요하면 SQL Server Distributed Replay를 사용할 수 있으나, 데모 범위에서는 A(권장) 또는 B로 충분합니다.

## 원칙
- baseline과 replay는 **같은 부하·같은 데이터 규모**여야 비교가 유효합니다(E의 결정적 프로파일 활용).
- 리플레이는 **격리된 대상**에 수행하고, 실제 Azure 리소스 프로비저닝은 이 데모 밖입니다.
- 다음 단계: `03_compare_waits.sql`로 wait/duration을 비교하고, `04_ai_report.md` 템플릿으로 자연어 회귀 리포트를 만듭니다.
