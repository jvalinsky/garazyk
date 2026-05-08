import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { shorten } from "./repo.js";

export interface CommandResult {
	command: string;
	code: number;
	stdout: string;
	stderr: string;
	combined: string;
}

export async function runShell(pi: ExtensionAPI, cwd: string, command: string, timeout = 120000): Promise<CommandResult> {
	const result = await pi.exec("bash", ["-lc", command], { cwd, timeout });
	const stdout = result.stdout ?? "";
	const stderr = result.stderr ?? "";
	return {
		command,
		code: result.code ?? 1,
		stdout,
		stderr,
		combined: shorten([stdout, stderr].filter(Boolean).join("\n")),
	};
}
