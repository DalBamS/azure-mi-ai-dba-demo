# 부하 스모크 (기존 game-driver 재사용)

배포된 임시 환경에 **짧은 부하**를 흘려 마이그레이션이 실제 트랜잭션 경로를 깨지
않는지(회귀) 확인한다. 새 드라이버를 만들지 않고 저장소의 `workload/game-driver/`를
그대로 재사용한다.

## CI 에서 (db-ci.yml `smoke-load` job)
`DEPLOY_ENABLED=true` 일 때만 동작한다. 접속정보는 **secrets/OIDC**로 주입하며 하드코딩하지 않는다.
```bash
pip install -r workload/game-driver/requirements.txt
python workload/game-driver/driver.py
```
환경변수(짧게):
```
WORKLOAD_CONCURRENCY=2
WORKLOAD_DURATION_SECONDS=30
AUTH_MODE=aad-integrated        # CI 는 OIDC/관리형 ID 권장
```

## 로컬에서 (수동)
```powershell
Copy-Item .env.example .env   # SQLMI_SERVER 등 채우기(비밀은 Key Vault 권장)
python .\workload\game-driver\driver.py
```

## 스모크 합격 기준
- 드라이버가 오류 없이 지정 시간 동안 트랜잭션을 커밋(재화 이체/인벤 업데이트/랭킹 조회).
- 신규 소프트삭제 필터드 인덱스(`IX_inventory_active`)·`season_id` 인덱스가 조회 경로를
  깨지 않음(예외/타임아웃 없음).
- 실패 시 로그는 `ai-failure-summary` job 이 수집해 AI 요약으로 넘긴다.

> 참고: 스모크는 "성능 벤치마크"가 아니라 "배포 후 기본 동작 확인"이다. 규모 있는 부하는
> pre-prod(F: 캡처→리플레이) 데모에서 다룬다.
