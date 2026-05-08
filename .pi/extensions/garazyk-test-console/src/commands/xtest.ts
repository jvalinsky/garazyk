import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { runShell } from "../exec.js";
import { repoRoot, shellQuote } from "../repo.js";
import { formatTestClassList, readTestMain } from "../parsers/testMain.js";
import { formatXCTestSummary, parseXCTestOutput } from "../parsers/xctest.js";

export function registerXTest(pi: ExtensionAPI): void {
	pi.registerCommand("xtest", {
		description: "Run Garazyk XCTest: /xtest <filter>|list|audit-registration",
		handler: async (args, ctx) => {
			const root = repoRoot(ctx.cwd);
			const trimmed = args.trim();
			if (!trimmed || trimmed === "help") {
				ctx.ui.notify("Usage: /xtest list | /xtest audit-registration | /xtest ClassName[/method]", "info");
				return;
			}

			if (trimmed === "list") {
				ctx.ui.notify(formatTestClassList(readTestMain(root)), "info");
				return;
			}

			const logDir = "/tmp/pi-garazyk-tests";
			mkdirSync(logDir, { recursive: true });
			const stamp = new Date().toISOString().replace(/[:.]/g, "-");
			const logPath = join(logDir, `xtest-${stamp}.log`);

			let command: string;
			let title: string;
			if (trimmed === "audit-registration" || trimmed === "audit") {
				command = "if [ ! -x ./build/tests/AllTests ]; then echo 'Missing ./build/tests/AllTests; build AllTests first'; exit 127; fi; PDS_TEST_REGISTRATION_AUDIT=1 ./build/tests/AllTests";
				title = "XCTest registration audit";
			} else {
				command = `if [ ! -x ./build/tests/AllTests ]; then echo 'Missing ./build/tests/AllTests; build AllTests first'; exit 127; fi; ./build/tests/AllTests -XCTest ${shellQuote(trimmed)}`;
				title = `XCTest ${trimmed}`;
			}

			ctx.ui.setStatus("garazyk-test", `xtest: ${trimmed}`);
			const result = await runShell(pi, root, command, 10 * 60 * 1000);
			writeFileSync(logPath, result.combined, "utf8");
			ctx.ui.setStatus("garazyk-test", undefined);

			const summary = parseXCTestOutput(result.combined);
			ctx.ui.notify(formatXCTestSummary(title, result.code, summary, logPath), result.code === 0 ? "success" : "error");
		},
	});
}
