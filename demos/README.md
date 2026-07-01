# /demos — 데모 시나리오 (라이프사이클별)

각 데모는 **공통 패턴**을 따릅니다: 자연어 → 다단계 자동 진단 → 검증(Eval) → 사람 승인.

> 운영(Runtime) 데모 A/B/C/M과 Pre-prod 데모 E/F/G/O는 발표용 런북과 SQL/스크립트 검증팩까지 준비되어 있습니다.
> CI/CD 데모(I/J/K)는 아직 placeholder입니다.

## 라이프사이클 매핑
| 단계 | 데모 | 위치 |
|------|------|------|
| **Pre-prod** | E, F, G, O | `pre-prod/` |
| **CI/CD** | I, J, K | `cicd/` |
| **운영(Runtime)** | A, B, C, M | `runtime/` |

## 하네스 원칙
- 값싼 반복 = **SLM** (Phi-4, Foundry Local/Ollama)
- 복잡한 해석 = **LLM** (클라우드)
- 안전 연결 = **MCP** (읽기전용 원칙)
