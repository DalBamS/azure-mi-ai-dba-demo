import { createApp } from "./api/server.js";
import { createAiClient, resolveAiEndpointHost, resolveAiModel } from "./ai/client.js";
import { resolveMode } from "./runner/index.js";

const port = Number.parseInt(process.env.COCKPIT_PORT ?? "5177", 10);
const aiClient = createAiClient();
const app = createApp({ aiClient });

app.listen(port, () => {
  const mode = resolveMode();
  console.log(`[cockpit] server listening on http://localhost:${port} (mode: ${mode})`);
  console.log(
    `[cockpit] ai mode: ${aiClient.mode}; model: ${resolveAiModel()}; endpoint host: ${resolveAiEndpointHost()}`,
  );
  if (mode === "mock") {
    console.log("[cockpit] mock mode — no Managed Instance will be contacted.");
  }
});
