<#
    scripts\inflate-leaderboard.ps1 — 데모 A(느린쿼리·인덱스) 전용, 가역적 대용량화.

    목적:
        데모 A는 `issue-injection\01_missing_index.sql`로 IX_leaderboard_rating 을
        DROP 한 뒤 `demos\runtime\A-slow-query-index\01_reproduce.sql` 의
            SELECT TOP(100) ... FROM dbo.leaderboard WHERE season = 1 ORDER BY rating DESC
        가 풀스캔되게 만드는 데모다. 그러나 smoke 시드(season=1, player당 1행 ≈ 1000행)
        규모에선 인덱스 유무와 무관하게 logical reads 가 거의 같아 seek vs scan 격차가
        눈에 띄지 않는다.
        이 쿼리는 season=1 만 조회하므로, season 을 대량 추가하면 결과셋(season=1)은
        작게 유지되면서 스캔 비용만 커진다 → 인덱스 seek(싸다) vs 풀스캔(비싸다) 격차가
        극대화되어 logical reads / wall-clock 체감이 살아난다.

    사용법:
        .\scripts\inflate-leaderboard.ps1 -Seasons 500     # 대용량화(멱등)
        .\scripts\inflate-leaderboard.ps1 -Reset           # 원복(season=1 원본만 남김)
        .\scripts\inflate-leaderboard.ps1 -Seasons 500 -Database gamedb

    원복법:
        -Reset 으로 season <> 1 행을 모두 삭제 → 완전 가역.

    주의:
        데모 A 전용 셋업이다. 발표가 끝나면 반드시 `-Reset` 으로 정리하라.
        비밀 하드코딩 없음 — 접속 정보는 전부 .env / 환경변수 기반(lib.ps1 재사용).
#>
[CmdletBinding()]
param(
    [int] $Seasons = 500,
    [switch] $Reset,
    [string] $Database
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
Import-DotEnv

$connArgs = Get-SqlcmdArgs -Database $Database

if ($Reset) {
    Write-Warning 'Reset requested: deleting inflated leaderboard rows (season <> 1)...'
    $resetSql = @'
SET NOCOUNT ON;
DELETE FROM dbo.leaderboard WHERE season <> 1;
SELECT COUNT(*) AS leaderboard_rows FROM dbo.leaderboard;
'@
    & sqlcmd @connArgs -b -Q $resetSql
    if ($LASTEXITCODE -ne 0) { throw "Reset failed (exit $LASTEXITCODE)." }
    Write-Host 'Reset complete (season=1 원본만 남음).' -ForegroundColor Green
    return
}

if ($Seasons -lt 1) { throw "Seasons must be >= 1 (got $Seasons)." }

# 멱등·집합기반 inflate: season=1 행을 복제해 season = 2..(1+Seasons) 생성.
# PK_leaderboard(season, player_id) 이므로 IF NOT EXISTS 로 중복(재실행)을 회피한다.
$inflateSql = @'
SET NOCOUNT ON;
DECLARE @s INT = 2, @max INT = 1 + $(Seasons);
WHILE @s <= @max
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.leaderboard WHERE season = @s)
        INSERT dbo.leaderboard (season, player_id, rating, wins, losses, rank_pos)
        SELECT @s, player_id, rating, wins, losses, rank_pos
        FROM dbo.leaderboard WHERE season = 1;
    SET @s += 1;
END
SELECT COUNT(*) AS leaderboard_rows FROM dbo.leaderboard;
'@

Write-Host "Inflating leaderboard: season 2..$((1 + $Seasons)) (from season=1 template)..."
& sqlcmd @connArgs -b -Q $inflateSql -v Seasons=$Seasons
if ($LASTEXITCODE -ne 0) { throw "Inflate failed (exit $LASTEXITCODE)." }
Write-Host 'Inflate complete. 발표 후 정리: .\scripts\inflate-leaderboard.ps1 -Reset' -ForegroundColor Green
