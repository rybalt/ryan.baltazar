/**
 * orchestrator-rules — inject the diff-coder delegation rule into the
 * interactive (tui) system prompt only.
 *
 * Route Y: subagent workers spawn with `--mode json -p`, so `ctx.mode !== "tui"`
 * for them — they never inherit this rule. The active delegation behavior lives
 * here (orchestrator-only) rather than in APPEND_SYSTEM.md (which loads in the
 * worker too).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const baseDir = dirname(fileURLToPath(import.meta.url));

let rules = "";
try {
	rules = readFileSync(join(baseDir, "delegation-rules.md"), "utf-8").trim();
} catch {
	// Missing rules file → inject nothing (handler no-ops below).
}

export default function (pi: ExtensionAPI) {
	pi.on("before_agent_start", async (event, ctx) => {
		if (ctx.mode !== "tui" || !rules) return undefined;
		return { systemPrompt: `${event.systemPrompt}\n\n${rules}` };
	});
}
