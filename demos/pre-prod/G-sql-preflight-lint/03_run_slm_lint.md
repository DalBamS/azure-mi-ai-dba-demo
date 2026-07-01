# G — 로컬 SLM으로 린트 실행하기 (03)

정적 린팅은 **값싸고 반복적인** 작업이라 클라우드 LLM보다 **로컬 SLM(Phi-4급)** 이 적합합니다. 배포마다 수십~수백 개 객체를 훑는 데 토큰 비용/지연/데이터 반출 없이 돌릴 수 있습니다. (복잡한 원인 해석은 LLM으로 에스컬레이션 — 하네스의 SLM↔LLM 분업.)

## 왜 SLM인가 (발표 포인트)
- **비용**: 배치 린팅은 호출 수가 많음 → 로컬 SLM은 호출당 비용 0.
- **지연**: CI/pre-flight 게이트에 인라인으로 넣어도 빠름.
- **데이터 경계**: SQL 정의가 외부로 나가지 않음(온프렘/격리 요건에 유리).
- **정형 작업**: 룰셋(`02_lint_rules.md`) 기반 패턴 매칭은 SLM이 충분히 잘함.

## 옵션 A — Foundry Local
```powershell
# 설치/모델 준비 (예시)
winget install Microsoft.FoundryLocal
foundry model run phi-4-mini
# OpenAI 호환 엔드포인트가 로컬에 뜸 (예: http://localhost:5273/v1)
```

## 옵션 B — Ollama
```powershell
winget install Ollama.Ollama
ollama pull phi4
ollama run phi4      # 또는 http://localhost:11434 API 사용
```

## 린트 호출 (개념 스크립트)
`01_collect_objects.sql`의 1번 결과(모듈 정의)를 객체별로 아래 프롬프트에 넣어 로컬 엔드포인트에 POST합니다. (실제 파이프라인은 CI 스텝/작은 스크립트로 감싸며, 엔드포인트/키는 환경변수로만 — **비밀 하드코딩 금지**.)

```powershell
# 예시: Ollama REST에 단일 객체 린트 요청
$def = Get-Content .\one_module.sql -Raw
$rules = Get-Content .\02_lint_rules.md -Raw
$body = @{
  model  = "phi4"
  stream = $false
  prompt = @"
$([string]::Format('{0}', $rules))

아래 T-SQL 객체를 위 룰셋으로 정적 린팅하라. 반드시 룰셋의 JSON 출력 계약만 반환하라(설명 금지).
객체:
$def
"@
} | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType 'application/json'
```

> **배치 실행**: 여러 객체를 한 번에 린트하려면 [`run_batch_lint.ps1`](./run_batch_lint.ps1)을 쓰세요 — `01_collect_objects.sql` 1번 결과를 객체별 `.sql`로 내보낸 폴더를 넘기면 룰셋을 적용해 객체별/통합 JSON을 생성합니다(엔드포인트·키는 환경변수만, 비밀 하드코딩 없음). 예: `.\run_batch_lint.ps1 -InputDir .\objects`.

## 프롬프트 템플릿 (핵심)
> 너는 T-SQL 정적 분석기다. 아래 룰셋(L1~L7)만 사용해 주어진 객체의 안티패턴을 찾아라. 각 발견을 `{object, rule, severity, evidence, fix}` JSON 배열로만 출력하라. 근거(evidence)는 원문 구절을 인용하라. 확실하지 않으면 포함하지 마라(오탐 최소화).

## 기대 결과 (샘플 객체 기준)
`dbo.usp_preflight_badexample`에 대해 최소 L1(암묵적 형변환)·L2(non-SARGable YEAR)·L3(leading wildcard)가 High/Medium으로 검출되어야 합니다. `04_eval.sql`로 이 신호가 실제 존재하는지 정적 검증합니다.
