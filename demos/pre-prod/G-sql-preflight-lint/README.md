# G — 배포 전 SQL Pre-flight 정적검증 (SLM)

배포 직전 SP/쿼리를 **로컬 SLM(Phi-4급)** 이 배치 린팅해 누락 인덱스·non-SARGable·암묵적 형변환·풀스캔·플랜 취약 패턴을 잡아냅니다. 값싸고 반복적인 정형 작업이라 클라우드 LLM보다 **로컬 SLM**이 비용/지연/데이터경계 면에서 적합합니다.

## 구성 파일
| 파일 | 역할 |
|------|------|
| `00_sample_bad_sql.sql` | 린터가 잡을 안티패턴 proc(격리 데모 객체) 생성 |
| `01_collect_objects.sql` | (읽기전용) 모듈 정의 + CONVERT_IMPLICIT/스캔/누락인덱스 근거 수집 |
| `02_lint_rules.md` | L1~L7 린트 룰셋 + JSON 출력 계약 |
| `03_run_slm_lint.md` | Foundry Local/Ollama로 Phi-4 실행 + 프롬프트 템플릿 |
| `04_eval.sql` | 샘플 객체에 목표 안티패턴이 실제 존재하는지 정적 검증 |
| `05_rollback.sql` | 샘플 proc 제거 |

## 발표 흐름
1. `00_sample_bad_sql.sql`로 안티패턴 proc(`dbo.usp_preflight_badexample`) 생성.
2. `01_collect_objects.sql`로 린트 대상 정의와 계획 신호(암묵적 형변환/스캔/누락 인덱스)를 읽기전용 수집.
3. `03_run_slm_lint.md`대로 로컬 SLM(Phi-4)에 룰셋+객체를 넣어 린트 실행 → `{object,rule,severity,evidence,fix}` JSON 획득.
4. `04_eval.sql`로 목표 안티패턴(L1/L2/L3)이 실제 존재함을 정적 확인(린트 결과 신뢰성 근거).
5. 데모 후 `05_rollback.sql`로 샘플 proc 정리.

## 왜 SLM인가 (하네스 분업)
- 배포마다 수십~수백 객체를 훑는 **값싼 반복** → 로컬 SLM(호출 비용 0, 저지연, 데이터 반출 없음).
- 복잡한 근본원인 해석은 **LLM**으로 에스컬레이션. 연결/조회는 **MCP 읽기전용**.

## 기존 수동 방식 vs AI 하네스 방식

| 단계 | 기존 DBA 수동 방식 | AI 하네스 방식 |
|------|-------------------|----------------|
| 리뷰 범위 | 시간상 일부 SP만 육안 리뷰 | SLM이 **전체 배치**를 일괄 린팅 |
| 안티패턴 탐지 | 경험 있는 DBA만 형변환/SARGability 포착 | 룰셋(L1~L7) 기반 일관 탐지 |
| 근거 | "이거 느릴 것 같다"는 지적 | 계획의 CONVERT_IMPLICIT/Scan + missing-index DMV 근거 |
| 비용/속도 | 사람 시간 = 병목, CI에 못 넣음 | 로컬 SLM = 저비용·저지연 → CI/pre-flight 게이트 인라인 |
| 데이터 경계 | 외부 도구에 코드 반출 우려 | 로컬 실행 → 코드가 환경 밖으로 안 나감 |
| 산출물 | 구두/메모 | `{rule,severity,evidence,fix}` 정형 JSON → 승인 리뷰 |

**발표 대본**
> (수동) "배포 전에 SP를 다 볼 시간은 없어서, 결국 눈에 익은 몇 개만 보고 넘어갔습니다. 형변환이나 SARGability 문제는 경험 많은 사람만 잡았고, CI에 넣을 수도 없었죠."
> (AI) "린팅은 값싸고 반복적인 정형 작업이라 로컬 SLM에 딱 맞습니다. 배포 배치 전체를 룰셋으로 훑어 근거(실행계획의 암묵적 형변환·스캔, 누락 인덱스 DMV)와 함께 수정안을 JSON으로 냅니다. 코드가 밖으로 나가지 않고 CI 게이트에 인라인으로 들어갑니다. 복잡한 해석이 필요할 때만 클라우드 LLM으로 넘깁니다."

## Eval 기준
- `04_eval.sql`에서 L1/L2/L3가 PASS(샘플 객체에 안티패턴 존재)로 확인.
- SLM 린트 결과가 최소 이 세 규칙을 검출(오탐 최소화 프롬프트 준수).

## 정리(cleanup)
- `05_rollback.sql`로 샘플 proc 제거.
