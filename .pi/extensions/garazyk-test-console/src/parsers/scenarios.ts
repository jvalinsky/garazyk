import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export interface ScenarioInfo {
	id: string;
	module: string;
	description: string;
	needsPds2: boolean;
}

export interface ScenarioReport {
	path: string;
	scenario: string;
	ok: boolean;
	duration_s?: number;
	summary: { passed: number; failed: number; skipped: number; total: number };
	steps: Array<{ name: string; status: "passed" | "failed" | "skipped"; detail: string; duration_ms: number }>;
}

export function readScenarioRegistry(repoRoot: string): ScenarioInfo[] {
	const path = join(repoRoot, "scripts/scenarios/run_scenario.py");
	const source = readFileSync(path, "utf8");
	const registry = source.match(/SCENARIO_REGISTRY\s*=\s*\[([\s\S]*?)\n\]/)?.[1] ?? "";
	return Array.from(registry.matchAll(/\("([0-9]+)",\s*"([^"]+)",\s*"([^"]+)",\s*(True|False)\)/g)).map((m) => ({
		id: m[1],
		module: m[2],
		description: m[3],
		needsPds2: m[4] === "True",
	}));
}

export function formatScenarioList(items: ScenarioInfo[]): string {
	const lines = ["ATProto scenarios", "", "ID   PDS2  Description"];
	for (const item of items) lines.push(`${item.id.padEnd(4)} ${item.needsPds2 ? "yes ": "    "}  ${item.description}`);
	return lines.join("\n");
}

export function latestScenarioReports(repoRoot: string, limit = 8): ScenarioReport[] {
	const dir = join(repoRoot, "scripts/scenarios/reports");
	if (!existsSync(dir)) return [];
	const files = readdirSync(dir)
		.filter((f) => f.endsWith(".json"))
		.map((f) => join(dir, f))
		.sort()
		.reverse()
		.slice(0, limit);
	const reports: ScenarioReport[] = [];
	for (const path of files) {
		try {
			const data = JSON.parse(readFileSync(path, "utf8"));
			reports.push({
				path,
				scenario: data.scenario ?? "unknown",
				ok: Boolean(data.ok),
				duration_s: data.duration_s,
				summary: data.summary ?? { passed: 0, failed: 0, skipped: 0, total: 0 },
				steps: Array.isArray(data.steps) ? data.steps : [],
			});
		} catch {
			// Ignore corrupt partial reports.
		}
	}
	return reports;
}

export function formatScenarioReports(reports: ScenarioReport[]): string {
	if (reports.length === 0) return "No scenario JSON reports found in scripts/scenarios/reports.";
	const lines = ["Latest scenario reports", ""];
	for (const r of reports) {
		lines.push(`${r.ok ? "PASS" : "FAIL"} ${r.scenario} (${r.summary.passed}/${r.summary.total} passed, ${r.summary.skipped} skipped)${r.duration_s ? ` ${r.duration_s}s` : ""}`);
		for (const step of r.steps.filter((s) => s.status === "failed").slice(0, 5)) {
			lines.push(`  - ${step.name}${step.detail ? ` — ${step.detail}` : ""}`);
		}
	}
	return lines.join("\n");
}
