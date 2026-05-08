import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { runShell } from "../exec.js";
import { repoRoot } from "../repo.js";
import { formatScenarioList, formatScenarioReports, latestScenarioReports, readScenarioRegistry } from "../parsers/scenarios.js";

export function registerScenarios(pi: ExtensionAPI): void {
	pi.registerCommand("scenarios", {
		description: "Manage ATProto scenarios: /scenarios list|run <ids>|report|setup|teardown",
		handler: async (args, ctx) => {
			const root = repoRoot(ctx.cwd);
			const tokens = args.trim().split(/\s+/).filter(Boolean);
			const sub = tokens.shift() ?? "list";

			if (sub === "list") {
				ctx.ui.notify(formatScenarioList(readScenarioRegistry(root)), "info");
				return;
			}

			if (sub === "report" || sub === "reports") {
				ctx.ui.notify(formatScenarioReports(latestScenarioReports(root)), "info");
				return;
			}

			if (sub === "setup") {
				const flags = tokens.filter((t) => ["--binary", "--pds2", "--wait-only"].includes(t));
				ctx.ui.setStatus("garazyk-scenarios", "setup running");
				const result = await runShell(pi, root, `./scripts/scenarios/setup_local_network.sh ${flags.join(" ")}`, 5 * 60 * 1000);
				ctx.ui.setStatus("garazyk-scenarios", result.code === 0 ? "scenarios: ready" : undefined);
				ctx.ui.notify(result.combined || "Scenario setup complete", result.code === 0 ? "success" : "error");
				return;
			}

			if (sub === "teardown") {
				const binary = tokens.includes("--binary") ? " --binary" : "";
				const result = await runShell(pi, root, `./scripts/scenarios/setup_local_network.sh --teardown${binary}`, 2 * 60 * 1000);
				ctx.ui.setStatus("garazyk-scenarios", undefined);
				ctx.ui.notify(result.combined || "Scenario teardown complete", result.code === 0 ? "success" : "error");
				return;
			}

			if (sub === "run") {
				const registry = readScenarioRegistry(root);
				const ids = tokens.filter((t) => /^\d+$/.test(t));
				const flags = tokens.filter((t) => t.startsWith("--"));
				if (ids.some((id) => registry.find((s) => s.id === id)?.needsPds2) && !flags.includes("--pds2")) {
					ctx.ui.notify("Selected scenario requires PDS2. Add --pds2 after ensuring the network was started with --pds2.", "warning");
				}
				const logDir = "/tmp/pi-garazyk-tests";
				mkdirSync(logDir, { recursive: true });
				const logPath = join(logDir, `scenarios-${new Date().toISOString().replace(/[:.]/g, "-")}.log`);
				const command = `python3 scripts/scenarios/run_scenario.py ${[...ids, ...flags].join(" ")}`;
				ctx.ui.setStatus("garazyk-scenarios", `running ${ids.join(",") || "all"}`);
				const result = await runShell(pi, root, command, 20 * 60 * 1000);
				writeFileSync(logPath, result.combined, "utf8");
				ctx.ui.setStatus("garazyk-scenarios", undefined);
				const reports = latestScenarioReports(root, Math.max(3, ids.length || 3));
				ctx.ui.notify(`${formatScenarioReports(reports)}\n\nLog: ${logPath}`, result.code === 0 ? "success" : "error");
				return;
			}

			ctx.ui.notify("Usage: /scenarios list | setup [--binary] [--pds2] | run <ids> [--pds2] | report | teardown [--binary]", "info");
		},
	});
}
