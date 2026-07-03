import { createApp } from "./api/server.js";
import { resolveMode } from "./runner/index.js";

const port = Number.parseInt(process.env.COCKPIT_PORT ?? "5177", 10);
const app = createApp();

app.listen(port, () => {
  const mode = resolveMode();
  console.log(`[cockpit] server listening on http://localhost:${port} (mode: ${mode})`);
  if (mode === "mock") {
    console.log("[cockpit] mock mode — no Managed Instance will be contacted.");
  }
});
