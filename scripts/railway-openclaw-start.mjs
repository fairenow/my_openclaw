#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const stateDir = process.env.OPENCLAW_STATE_DIR?.trim()
  ? path.resolve(process.env.OPENCLAW_STATE_DIR)
  : path.join(os.homedir(), ".openclaw");
const configPath = process.env.OPENCLAW_CONFIG_PATH?.trim()
  ? path.resolve(process.env.OPENCLAW_CONFIG_PATH)
  : path.join(stateDir, "openclaw.json");

mkdirSync(path.dirname(configPath), { recursive: true });

let config = {};
if (existsSync(configPath)) {
  const raw = readFileSync(configPath, "utf8").trim();
  if (raw) {
    try {
      config = JSON.parse(raw);
    } catch (error) {
      const backupPath = `${configPath}.invalid-${Date.now()}`;
      renameSync(configPath, backupPath);
      console.warn(`OpenClaw Railway preflight: invalid config moved to ${backupPath}`);
      config = {};
    }
  }
}

// A persisted Codex plugin install from another environment can block the whole
// Gateway when its compiled entry is missing in the Railway image. TC Remote
// does not require the Codex harness to use OpenClaw, so remove only that stale
// plugin registration and leave every other OpenClaw setting intact.
const plugins = config && typeof config === "object" ? config.plugins : undefined;
if (plugins && typeof plugins === "object") {
  if (plugins.entries && typeof plugins.entries === "object" && plugins.entries.codex) {
    delete plugins.entries.codex;
    console.warn("OpenClaw Railway preflight: removed stale plugins.entries.codex registration");
  }
  if (Array.isArray(plugins.allow)) {
    plugins.allow = plugins.allow.filter((id) => id !== "codex");
  }
  if (Array.isArray(plugins.deny)) {
    plugins.deny = plugins.deny.filter((id) => id !== "codex");
  }
}

config.gateway ??= {};
config.gateway.mode = "local";
config.gateway.http ??= {};
config.gateway.http.endpoints ??= {};
config.gateway.http.endpoints.chatCompletions ??= {};
config.gateway.http.endpoints.chatCompletions.enabled = true;

writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
console.log(`OpenClaw Railway preflight: config ready at ${configPath}`);

const port = process.env.PORT?.trim() || "18789";
const child = spawn(
  process.execPath,
  ["openclaw.mjs", "gateway", "--bind", "lan", "--port", port, "--allow-unconfigured"],
  { cwd: "/app", env: process.env, stdio: "inherit" },
);

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    if (!child.killed) child.kill(signal);
  });
}

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
