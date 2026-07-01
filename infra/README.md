# /infra — Azure 인프라 (파라미터화, 실행 보류)

Azure SQL Managed Instance 및 보안 스택을 프로비저닝하기 위한 **Bicep + az CLI** 스크립트를 둡니다.

> ⚠️ **실행 보류**: 이번 단계에서는 스크립트를 준비만 합니다. 실제 리소스 생성은
> 사용자가 환경 정보를 전달한 뒤 진행합니다. 파라미터는 모두 외부화되어 있어야 합니다.

## 계획된 구성 요소
- Azure SQL Managed Instance (General Purpose, 4~8 vCore)
- 가상 네트워크 / 서브넷 / NSG (MI 요구사항)
- Microsoft Defender for SQL
- SQL Audit → Log Analytics Workspace
- Vulnerability Assessment
- Data Discovery & Classification
- Key Vault (비밀 저장)

## 파일 (예정)
- `main.bicep` — 오케스트레이션 진입점
- `modules/` — sqlmi, network, monitoring, security 모듈
- `main.parameters.example.json` — 파라미터 예시 (실값 금지)
- `deploy.ps1` / `deploy.sh` — az CLI 배포 래퍼 (실행 보류)

## 원칙
- 비밀/커넥션스트링 하드코딩 금지 → Key Vault 참조.
- 모든 이름/규모/리전은 파라미터화.
