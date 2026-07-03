# cockpit/infra/optional — 선택 인프라 (추론 엔드포인트)

데모 조종석(cockpit) **자체**는 별도의 Azure 리소스가 필요 없습니다. 목(mock) 모드는
네트워크·프로세스·비밀에 전혀 접근하지 않고, 라이브 모드는 리포 루트의 기존
[`/infra`](../../../infra/README.md) 스택(Managed Instance · VNet/NSG · Defender for SQL ·
Log Analytics · Data Classification · Key Vault)만 있으면 동작합니다.

즉 **MI 외에 추가로 필요한 것은 (선택적) 추론 엔드포인트 하나뿐**입니다. AI 스텝
(F 회귀 리포트, G Pre-flight 린트 등)이 자연어 산출물을 생성할 때 사용할 모델 호스팅입니다.

## 데이터 경계와 2계층 모델

| 계층 | 런타임 | 데이터 경계 | Azure 리소스 |
|---|---|---|---|
| SLM (값싼 반복) | Foundry Local (로컬 OpenAI 호환) | **경계 안** | 없음 (로컬 실행) |
| LLM (복잡한 해석) | Azure AI Foundry 관리형 엔드포인트 | 자체 구독/테넌트/리전 → 프라이빗 네트워킹 시 경계 안 | Cognitive Services (AIServices) + 모델 배포 |

> 자세한 원칙은 [`docs/architecture.md`](../../../docs/architecture.md) §3와
> [`mcp/README.md`](../../../mcp/README.md)의 "추론 엔드포인트" 절을 참고하세요.

## 프로비저닝 (선택)

SLM(Foundry Local)은 로컬 설치만 하면 되므로 Azure 스크립트가 없습니다.
LLM(Azure AI Foundry)을 **자체 구독에** 두고 싶을 때만 아래 스크립트를 사용합니다.

```powershell
# 1) 검증만 (실제 생성 없음) — 기본 동작
.\deploy-ai-foundry.ps1 -SubscriptionId <sub> -ResourceGroup rg-mi -AccountName <your-foundry>

# 2) 실제 생성 (환경 확정 후에만)
.\deploy-ai-foundry.ps1 -SubscriptionId <sub> -ResourceGroup rg-mi -AccountName <your-foundry> -Execute

# 3) 배포 검증 (엔드포인트/배포 목록 확인)
.\deploy-ai-foundry.ps1 -SubscriptionId <sub> -ResourceGroup rg-mi -AccountName <your-foundry> -Verify
```

성공 후 조종석/하네스가 사용할 환경 변수를 주입합니다(비밀은 셸/시크릿 스토어에서만):

```powershell
$env:LLM_ENDPOINT = "https://<your-foundry>.openai.azure.com/"
$env:LLM_API_KEY  = "<from-portal-or-az>"
$env:LLM_MODEL    = "<your-deployment-name>"   # 예: gpt-4o-mini 배포명
```

## 원칙
- **실행 보류가 기본**: `-Execute` 없이는 `--what-if`/조회만 수행합니다.
- **멱등**: 이미 존재하면 생성하지 않고 건너뜁니다.
- **플레이스홀더 전용**: 실제 구독·리소스·키를 소스에 넣지 않습니다.
- **비밀 미하드코딩**: 키는 `az cognitiveservices account keys list`로 조회하거나 포털에서 받아 env로만 주입합니다.
