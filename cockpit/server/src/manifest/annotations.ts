export interface DemoAnnotation {
  summary: string;
  whyAi: string;
  aiHint?: string;
}

export const DEMO_ANNOTATIONS: Record<string, DemoAnnotation> = {
  A: {
    summary:
      "랭킹 Top-N 조회 지연을 재현하고 DMV/실행계획 근거로 누락된 `IX_leaderboard_rating` 인덱스를 찾아 승인 후 복구하는 운영 데모입니다.",
    whyAi:
      "AI 하네스가 자연어 신고에서 근거 수집, 원인 식별, 수정안 제안, Eval 검증까지 묶어 DBA가 수동 창 전환 대신 승인과 판단에 집중하게 합니다.",
    aiHint:
      "랭킹(leaderboard) 조회가 느립니다. DMV/실행계획 근거로 원인과 해결책(인덱스 포함)을 알려주세요.",
  },
  B: {
    summary:
      "재화와 인벤토리 교차 업데이트에서 생긴 deadlock을 XEvents 근거로 분석해 상반된 락 순서를 근본 원인으로 짚는 데모입니다.",
    whyAi:
      "AI가 사라지기 쉬운 deadlock graph를 자동 해석하고 일관된 락 순서 패턴을 제안해, XML 수동 추적과 원인 누락 위험을 줄입니다.",
    aiHint: "deadlock이 발생했어요. 그래프와 세션 출력 근거로 원인과 재발 방지책을 설명해 주세요.",
  },
  C: {
    summary:
      "패치/통계 변경 뒤 앱 경로에서만 느려지는 plan regression을 SET 옵션 분리와 parameter sniffing 근거로 설명하는 데모입니다.",
    whyAi:
      "AI가 앱과 SSMS의 plan cache 차이, sniffed parameter, proc stats를 함께 모아 안전한 안정 plan 대안을 비교하게 합니다.",
    aiHint: "앱에서만 쿼리가 느려졌어요. plan regression 근거와 안전한 완화책을 정리해 주세요.",
  },
  M: {
    summary:
      "격리된 데모 MI의 취약 동적 SQL proc에서 SQL Injection 시도 흔적을 진단하고 파라미터화된 안전 구현을 제안하는 보안 운영 데모입니다.",
    whyAi:
      "AI가 audit/쿼리 텍스트/proc 정의를 함께 읽어 취약 코드 위치와 입력 패턴을 연결하고, 방어 관점의 수정안을 즉시 제시합니다.",
    aiHint: "SQL Injection 의심 흔적이 있어요. 출력 근거로 취약 지점과 안전한 수정 SQL을 제안해 주세요.",
  },
  E: {
    summary:
      "런칭 첫날 동접과 업무 비중 같은 자연어 요구를 Query Store 관측 근거에 맞춘 game-driver/HammerDB 부하 프로파일로 바꾸는 pre-prod 데모입니다.",
    whyAi:
      "AI가 실제 top query 패턴과 자연어 목표를 결합해 반복 가능한 워크로드 파라미터를 만들고, 부하 설계의 수작업 추정을 줄입니다.",
  },
  F: {
    summary:
      "업그레이드나 티어 변경 전 동일 워크로드를 캡처·리플레이하고 Query Store wait/duration delta로 회귀를 판정하는 데모입니다.",
    whyAi:
      "AI가 캡처/리플레이 비교 결과를 근거 인용 리포트로 요약해, 엑셀식 수동 대조 대신 배포 진행·보류 결정을 빠르게 합니다.",
  },
  G: {
    summary:
      "배포 전 저장 프로시저와 쿼리를 로컬 SLM 룰셋으로 린팅해 누락 인덱스, non-SARGable, 암묵적 형변환 등 플랜 취약 패턴을 잡는 데모입니다.",
    whyAi:
      "값싼 반복 검사는 로컬 SLM이 전체 배치를 일관되게 처리하고, 근거와 수정안을 JSON으로 남겨 DBA 리뷰 병목을 줄입니다.",
  },
  O: {
    summary:
      "게임 서비스의 닉네임·이메일·결제 같은 민감 컬럼을 자동 분류하고 DDM/RLS 정책 초안을 생성·적용·검증하는 보안 플래그십 데모입니다.",
    whyAi:
      "AI가 PII 후보 발견, 분류 태깅, 마스킹/RLS 초안, 카탈로그 기반 Eval을 연결해 개인정보 보호 게이트를 반복 가능하게 만듭니다.",
  },
  I: {
    summary:
      "자연어 스키마 변경 요청을 멱등 마이그레이션, 대칭 롤백, SQL Database Project 선언형 최종 상태로 동시에 바꾸는 Database-as-Code 데모입니다.",
    whyAi:
      "AI가 온라인·비파괴 가드와 롤백을 함께 생성하고 DACPAC 정합성까지 연결해 수동 DDL 작성의 누락과 drift를 줄입니다.",
  },
  J: {
    summary:
      "스키마 변경 PR의 대형 테이블 락, 비온라인 인덱스, breaking change, 데이터 손실, 롤백·보안 위험을 자동 리뷰하는 킬러 데모입니다.",
    whyAi:
      "AI가 같은 루브릭으로 매 PR을 스캔하고 근거와 suggestion을 붙여, 사람마다 다른 리뷰 편차와 위험한 머지를 줄입니다.",
  },
  K: {
    summary:
      "GitHub Actions가 DACPAC 빌드, 롤백 대칭성 lint, 배포 가드, drift/smoke, 실패 로그 AI 요약까지 수행하는 CI 파이프라인 데모입니다.",
    whyAi:
      "AI가 긴 실패 로그를 원인·영향·다음 조치로 요약하고, CI 게이트가 반복 검증을 자동화해 DBA가 배포 판단에 집중하게 합니다.",
  },
};
