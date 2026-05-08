import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { runShell } from "../exec.js";

export async function changedFiles(pi: ExtensionAPI, cwd: string): Promise<string[]> {
	const commands = [
		"git diff --name-only origin/main...HEAD 2>/dev/null",
		"git diff --name-only HEAD 2>/dev/null",
		"git diff --name-only 2>/dev/null",
	];
	for (const command of commands) {
		const result = await runShell(pi, cwd, command, 20000);
		const files = result.stdout.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
		if (files.length > 0) return files;
	}
	return [];
}
