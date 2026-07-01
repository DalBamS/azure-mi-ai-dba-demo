# /docs — 문서

데모의 개념/아키텍처/런북 문서를 둡니다.

## 계획된 문서
- `architecture.md` — AI 하네스 개념도(자연어 → 다단계 진단 → Eval → 사람 승인), SLM/LLM/MCP 역할.
- `demo-roadmap.md` — 라이프사이클별 데모 매핑(Pre-prod / CI/CD / 운영).
- `runbook.md` — 환경 구성 실행 순서 상세(루트 README 요약본의 확장).
- `security.md` — Defender/Audit/VA/Data Classification, 읽기전용 원칙.

## 핵심 메시지
AI가 게임 DB의 전 생애주기를 감싸는 하나의 **하네스**.
값싼 반복 = SLM(Phi-4 로컬), 복잡한 해석 = LLM(클라우드), 안전 연결 = MCP(읽기전용).
