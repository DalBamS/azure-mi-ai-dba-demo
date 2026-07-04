import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { describe, it, expect } from "vitest";
import { findRepoRoot, toRepoRelative } from "../src/manifest/paths.js";
import { loadManifest } from "../src/manifest/load.js";

const repoRoot = findRepoRoot();
const manifest = loadManifest(repoRoot);
const injectedIssueSteps = [
  "issue-injection/01_missing_index.rollback.sql",
  "issue-injection/01_missing_index.sql",
  "issue-injection/02_blocking_deadlock.rollback.sql",
  "issue-injection/02_blocking_deadlock.sessionA.sql",
  "issue-injection/02_blocking_deadlock.sessionB.sql",
  "issue-injection/03_plan_regression.rollback.sql",
  "issue-injection/03_plan_regression.sql",
  "issue-injection/06_sql_injection.rollback.sql",
  "issue-injection/06_sql_injection.sql",
];

function listFiles(dir: string, predicate: (file: string) => boolean): string[] {
  const files: string[] = [];
  const walk = (current: string): void => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const abs = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(abs);
        continue;
      }
      if (entry.isFile() && predicate(abs)) files.push(abs);
    }
  };
  walk(dir);
  return files.sort((a, b) => a.localeCompare(b));
}

function stripMarkdownLinkDecorators(target: string): string {
  return target.trim().replace(/^<|>$/g, "").split(/[?#]/, 1)[0]!;
}

function stripSqlComments(text: string): { stripped: string; hasClosedBlockComments: boolean } {
  let out = "";
  let i = 0;
  let inBlock = false;
  let inLine = false;
  let inString = false;

  while (i < text.length) {
    const c = text[i]!;
    const next = text[i + 1] ?? "";

    if (inLine) {
      if (c === "\n") {
        inLine = false;
        out += "\n";
      }
      i++;
      continue;
    }

    if (inBlock) {
      if (c === "*" && next === "/") {
        inBlock = false;
        i += 2;
      } else {
        i++;
      }
      continue;
    }

    if (inString) {
      out += c;
      if (c === "'" && next === "'") {
        out += next;
        i += 2;
        continue;
      }
      if (c === "'") inString = false;
      i++;
      continue;
    }

    if (c === "-" && next === "-") {
      inLine = true;
      i += 2;
      continue;
    }
    if (c === "/" && next === "*") {
      inBlock = true;
      i += 2;
      continue;
    }
    if (c === "'") inString = true;
    out += c;
    i++;
  }

  return { stripped: out, hasClosedBlockComments: !inBlock && !inString };
}

describe("repository static validation", () => {
  it("keeps demo markdown relative links resolvable", () => {
    const markdownFiles = listFiles(path.join(repoRoot, "demos"), (file) => file.endsWith(".md"));
    const missing: string[] = [];

    for (const file of markdownFiles) {
      const text = fs.readFileSync(file, "utf8");
      const links = text.matchAll(/!?\[[^\]]*]\(([^)\s]+)(?:\s+"[^"]*")?\)/g);
      for (const link of links) {
        const rawTarget = link[1]!;
        const target = stripMarkdownLinkDecorators(rawTarget);
        if (!target || target.startsWith("#") || /^[a-z][a-z0-9+.-]*:/i.test(target)) continue;
        if (target.includes("<") || target.includes(">")) continue;

        const resolved = path.resolve(path.dirname(file), target.replaceAll("/", path.sep));
        if (!fs.existsSync(resolved)) {
          missing.push(`${toRepoRelative(repoRoot, file)} -> ${rawTarget}`);
        }
      }
    }

    expect(missing).toEqual([]);
  });

  it("keeps SQL demo files parseable by static text guards", () => {
    const sqlFiles = listFiles(path.join(repoRoot, "demos"), (file) => file.endsWith(".sql"));
    expect(sqlFiles.length).toBeGreaterThan(0);

    for (const file of sqlFiles) {
      const text = fs.readFileSync(file, "utf8");
      const { stripped, hasClosedBlockComments } = stripSqlComments(text);
      expect(hasClosedBlockComments, `${toRepoRelative(repoRoot, file)} comments/strings`).toBe(true);
      expect(stripped, `${toRepoRelative(repoRoot, file)} merge markers`).not.toMatch(
        /^(<<<<<<<|=======|>>>>>>>)$/m,
      );
      expect(stripped.trim(), `${toRepoRelative(repoRoot, file)} content`).not.toHaveLength(0);
    }
  });

  it("parses repository PowerShell scripts with the PowerShell AST parser", () => {
    const roots = ["scripts", "infra", path.join("cockpit", "infra")].map((p) =>
      path.join(repoRoot, p),
    );
    const files = roots.flatMap((root) =>
      fs.existsSync(root) ? listFiles(root, (file) => file.endsWith(".ps1")) : [],
    );
    expect(files.length).toBeGreaterThan(0);

    const powerShell7 = path.join(
      process.env.ProgramFiles ?? "C:\\Program Files",
      "PowerShell",
      "7",
      "pwsh.exe",
    );
    const executable = fs.existsSync(powerShell7) ? powerShell7 : "pwsh";
    const script = String.raw`
$ErrorActionPreference = 'Stop'
$files = ConvertFrom-Json -InputObject $env:COCKPIT_PS_AST_FILES
$failed = @()
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
  if ($errors.Count -gt 0) {
    $messages = ($errors | ForEach-Object { $_.Message }) -join '; '
    $failed += "$file :: $messages"
  }
}
if ($failed.Count -gt 0) {
  Write-Error ($failed -join [Environment]::NewLine)
  exit 1
}
`;
    const result = spawnSync(executable, ["-NoProfile", "-NonInteractive", "-Command", script], {
      encoding: "utf8",
      env: { ...process.env, COCKPIT_PS_AST_FILES: JSON.stringify(files) },
      timeout: 30_000,
    });

    expect(result.status, result.stderr || result.stdout).toBe(0);
  });

  it("keeps committed JSON examples valid", () => {
    const jsonFiles = [
      path.join(repoRoot, "cockpit", "manifest.json"),
      ...listFiles(path.join(repoRoot, "mcp"), (file) => file.endsWith(".json")),
    ];

    for (const file of jsonFiles) {
      expect(
        () => JSON.parse(fs.readFileSync(file, "utf8")),
        toRepoRelative(repoRoot, file),
      ).not.toThrow();
    }
  });

  it("keeps demos step files plus curated issue-injection files exactly aligned with the generated manifest", () => {
    const diskSteps = listFiles(path.join(repoRoot, "demos"), (file) => {
      if (/README\.md$/i.test(file)) return false;
      return [".sql", ".py", ".ps1", ".md"].includes(path.extname(file).toLowerCase());
    })
      .map((file) => toRepoRelative(repoRoot, file))
      .concat(injectedIssueSteps)
      .sort((a, b) => a.localeCompare(b));
    const manifestSteps = manifest.demos
      .flatMap((demo) =>
        demo.steps.flatMap((step) => step.concurrentPaths ?? [step.path]),
      )
      .sort((a, b) => a.localeCompare(b));

    expect(manifestSteps).toEqual(diskSteps);
  });
});
