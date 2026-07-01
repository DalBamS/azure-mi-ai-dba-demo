# G — SQL Pre-flight 린트 룰셋 (02)

배포 전 SP/쿼리를 SLM이 **정적 린팅**할 때 적용하는 규칙입니다. 각 규칙은 게임 스키마(`/schema`)와 `00_sample_bad_sql.sql`의 안티패턴에 대응합니다.

| ID | 규칙 | 탐지 신호 | 위험 | 권고 |
|----|------|-----------|------|------|
| **L1 암묵적 형변환** | 컬럼과 파라미터/리터럴의 타입 불일치 | 계획의 `CONVERT_IMPLICIT`, `PlanAffectingConvert`; 예: `region VARCHAR` vs `@p NVARCHAR` | 컬럼 변환 → seek 불가, 스캔 | 파라미터 타입을 컬럼과 일치(`VARCHAR(16)`) |
| **L2 non-SARGable** | 컬럼에 함수/연산 적용 | `WHERE YEAR(col)=`, `col+0`, `ISNULL(col,..)=` | 인덱스 seek 불가 | 범위 조건으로 재작성(`col >= @start AND col < @end`) |
| **L3 leading-wildcard LIKE** | `LIKE '%...'` 선행 와일드카드 | `LIKE '%' + @x` | 풀스캔 | 접두 검색/전문검색/계산열 재설계 |
| **L4 풀스캔/누락 인덱스** | 계획의 Table/Clustered Index Scan + missing-index DMV | `PhysicalOp="Clustered Index Scan"`, `avg_user_impact` 높음 | IO 급증, 확장성 악화 | 적절한 커버링 인덱스 제안 |
| **L5 SELECT \*** | 불필요한 컬럼 반환 | `SELECT *` | IO/네트워크 낭비, 계획 취약 | 필요한 컬럼만 명시 |
| **L6 위험한 동적 SQL** | 문자열 연결 `EXEC(@sql)` | `EXEC (` + concat | SQL Injection | 파라미터화(`sp_executesql`) — 운영 M 데모 연계 |
| **L7 SET 옵션/플랜 취약** | 파라미터 스니핑 민감 SP | 편향 파라미터로 캐시된 플랜 | 앱 경로 회귀 | `OPTIMIZE FOR`/plan 강제 — 운영 C 데모 연계 |

## 심각도
- **High**: L1, L2, L4, L6 (성능·보안 직접 영향)
- **Medium**: L3, L7
- **Low**: L5

## 출력 계약(린터가 반환해야 하는 형식)
린터는 객체별로 다음 JSON 배열을 반환합니다(사람 승인 리뷰용):
```json
[
  {"object":"dbo.usp_preflight_badexample","rule":"L1","severity":"High",
   "evidence":"p.region = @region  (region VARCHAR vs @region NVARCHAR)",
   "fix":"declare @region VARCHAR(16) to match the column type"}
]
```
