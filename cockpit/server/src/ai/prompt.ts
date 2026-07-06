export interface ChatMessage {
  role: "system" | "user";
  content: string;
}

export interface BuildMessagesInput {
  question: string;
  contextText?: string;
}

const SYSTEM_PROMPT = [
  "당신은 AI 하네스 안에서 동작하는 시니어 Azure SQL Managed Instance DBA입니다.",
  "한국어로 답하세요. 읽기 전용 진단만 수행합니다.",
  "제공된 텔레메트리/DMV 출력만 해석하고, 없는 수치나 사실은 만들지 마세요.",
  "근본 원인을 식별하고, 적용 가능한 경우 정확한 T-SQL DDL 예시를 포함한 구체적 해결책을 제안하세요.",
  "제안된 DDL은 절대 자동 적용되지 않으며, 반드시 사람이 검토·승인 후 적용해야 한다고 항상 명시하세요.",
  "DIAGNOSE OUTPUT이 비어 있거나 부족하면, 먼저 diagnose/evidence 스텝을 실행해 달라고 말하세요.",
].join(" ");

export function buildMessages(input: BuildMessagesInput): ChatMessage[] {
  const context = input.contextText?.trim() || "(no diagnose output provided)";
  return [
    {
      role: "system",
      content: SYSTEM_PROMPT,
    },
    {
      role: "user",
      content: [
        "PRESENTER QUESTION:",
        input.question.trim(),
        "",
        "DIAGNOSE OUTPUT:",
        context,
      ].join("\n"),
    },
  ];
}
