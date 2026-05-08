import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { changedFiles } from "../parsers/git.js";
import { readTestMain } from "../parsers/testMain.js";
import { repoRoot } from "../repo.js";

function extractTestClassesFromFile(path: string): string[] {
	if (!existsSync(path)) return [];
	const source = readFileSync(path, "utf8");
	const names = new Set<string>();
	for (const match of source.matchAll(/@(interface|implementation)\s+([A-Za-z0-9_]+Tests)\b/g)) names.add(match[2]);
	return Array.from(names);
}

async function registrationWarnings(pi: ExtensionAPI, ctx: ExtensionContext): Promise<string[]> {
	const root = repoRoot(ctx.cwd);
	const files = (await changedFiles(pi, root)).filter((f) => /^Garazyk\/Tests\/.*Tests\.m$/.test(f));
	if (files.length === 0) return [];

	const registered = new Set(readTestMain(root).registeredClasses);
	const warnings: string[] = [];
	for (const file of files) {
		const classes = extractTestClassesFromFile(join(root, file));
		for (const className of classes) {
			if (!registered.has(className)) warnings.push(`${className} appears in ${file} but is not registered in Garazyk/Tests/test_main.m`);
		}
	}
	return warnings;
}

export function registerRegistrationGuard(pi: ExtensionAPI): void {
	pi.registerCommand("test-registration", {
		description: "Check changed XCTest files against test_main.m registration",
		handler: async (_args, ctx) => {
			const warnings = await registrationWarnings(pi, ctx);
			if (warnings.length === 0) ctx.ui.notify("No changed XCTest registration issues detected.", "success");
			else ctx.ui.notify(`XCTest registration warnings:\n${warnings.map((w) => `- ${w}`).join("\n")}\n\nRun /xtest audit-registration for runtime verification.`, "warning");
		},
	});

	pi.on("agent_end", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		const warnings = await registrationWarnings(pi, ctx);
		if (warnings.length > 0) {
			try {
				ctx.ui.notify(`XCTest registration warning:\n${warnings.slice(0, 5).map((w) => `- ${w}`).join("\n")}\nRun /xtest audit-registration.`, "warning");
			} catch {
				// The session may have been replaced or shut down while the git query was running.
			}
		}
	});
}
