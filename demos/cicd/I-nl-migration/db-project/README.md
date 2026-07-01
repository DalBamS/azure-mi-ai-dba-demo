# GameDb — SQL Database Project (Database-as-Code)

`leaderboard`/`inventory` 등 게임 스키마의 **선언형 최종 상태**를 담는 SQL Database
Project입니다. 데모 I 마이그레이션(`../migrations`)이 적용된 이후의 목표 스키마와 동일합니다.

## 두 가지 표현이 함께 있는 이유
- **마이그레이션 스크립트**(`../migrations/*.up/down.sql`): "어떻게 바꾸는가"(명령형, 롤백 포함).
- **SQL Database Project**(이 폴더): "무엇이 되어야 하는가"(선언형 최종 상태).
  빌드하면 `GameDb.dacpac`이 나오고, 배포 시 **SqlPackage/DacFx가 대상 DB와 diff**를 계산해
  필요한 변경만 적용합니다. 데모 K 파이프라인의 빌드 산출물이 바로 이 DACPAC입니다.

## 빌드 (로컬)
```bash
# .NET SDK + Microsoft.Build.Sql SDK 사용 (SDK-style 프로젝트)
# 이 폴더의 global.json 이 SDK 를 .NET 8 로 고정합니다(Microsoft.Build.Sql 2.2.0 검증 조합).
dotnet build GameDb.sqlproj -c Release
# 산출물: bin/Release/GameDb.dacpac
```
또는 SqlPackage 기반 도구체인에서 동일 .sqlproj를 빌드할 수 있습니다.

## 배포 (⚠ 보류 — 실제 배포 금지)
실제 배포는 하지 않습니다. 파이프라인/문서에서는 **명령 예시**로만 남깁니다.
```bash
# DryRun/스크립트 생성만 — 실제 적용 아님
sqlpackage /Action:Script \
  /SourceFile:bin/Release/GameDb.dacpac \
  /TargetServerName:<mi-fqdn> /TargetDatabaseName:gamedb \
  /OutputPath:deploy-preview.sql
# (실배포는 /Action:Publish 이며, 데모에서는 가드로 비활성)
```
- 접속정보/비밀은 **하드코딩 금지** — CI에서는 OIDC(`azure/login`) + secrets 사용.
- 파괴적 변경(컬럼/테이블 삭제)은 `/p:BlockOnPossibleDataLoss=true`(기본 true)로 차단.

## 구성
| 파일 | 내용 |
|------|------|
| `GameDb.sqlproj` | SDK-style 프로젝트(Microsoft.Build.Sql 2.2.0, DSP=Sql160, MI 호환 표면) |
| `Tables/players.sql` | 기준 엔터티 |
| `Tables/inventory.sql` | 핫 테이블 + 소프트삭제(마이그 002) |
| `Tables/currency_ledger.sql` | 동시성 경합 |
| `Tables/matches.sql` | 매치 기록 |
| `Tables/seasons.sql` | 시즌 마스터(마이그 001) |
| `Tables/leaderboard.sql` | 랭킹 + season_id(마이그 001) |
