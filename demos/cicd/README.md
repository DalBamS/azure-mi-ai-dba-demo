# CI/CD 데모 (배포 파이프라인 · Database DevOps)

핵심 개념 = **Database-as-Code + AI 리뷰·게이트**. 자연어로 스키마 변경을 만들고,
PR에서 위험을 AI가 진단하며, CI 파이프라인에 AI 게이트를 삽입한다. 기존 게임 스키마
(`players`/`inventory`/`currency_ledger`/`matches`/`leaderboard`) 기반.

| 코드 | 데모 | 개요 | 폴더 |
|------|------|------|------|
| **I** | 자연어 → 마이그레이션 + 롤백 | 자연어 요구 → idempotent 마이그레이션 + 대칭 롤백 + SQL Database Project(.sqlproj/DACPAC) | [`I-nl-migration/`](I-nl-migration/) |
| **J** | PR 위험 리뷰 에이전트 + 보안 게이트 (킬러) | 스키마 변경 PR의 락/breaking/데이터손실/롤백 위험 + 과잉권한·시크릿·마스킹 보안 게이트 | [`J-pr-risk-review/`](J-pr-risk-review/) |
| **K** | GitHub Actions 파이프라인 + AI 게이트 | DACPAC 빌드 -> (가드)배포 -> drift/회귀 -> 스모크 -> 실패 시 Copilot 요약 | [`K-actions-pipeline/`](K-actions-pipeline/) |

## 파이프라인으로서의 흐름
```
[I] 자연어->마이그레이션/DACPAC  ->  [J] PR 위험·보안 리뷰(머지 게이트)  ->  [K] CI 빌드·배포·검증·AI 요약
```
- **I**가 만든 `db-project` DACPAC이 **K** 파이프라인의 빌드 입력물이 된다.
- **J**의 위험 루브릭이 머지 전 게이트, **K**의 `migration-lint`가 머지 후 롤백 대칭성 게이트.

## 공통 패턴
자연어 -> 다단계 자동 진단 -> Eval -> 사람 승인.

## 안전/정책 (전 데모 공통)
- 실제 Azure 프로비저닝/배포 **없음**. 배포 지점은 가드/더미(`DEPLOY_ENABLED` 등).
- 비밀/커넥션스트링 **하드코딩 금지** — GitHub Actions는 `secrets` + OIDC(`azure/login`), 앱은 Key Vault.
- 모든 T-SQL은 idempotent. 파괴적 변경은 `BlockOnPossibleDataLoss=true`로 방어.

## 표준 도구
SQL Database Projects(Microsoft.Build.Sql) · DACPAC/DacFx · SqlPackage · `azure/sql-action` · `azure/login`(OIDC).
