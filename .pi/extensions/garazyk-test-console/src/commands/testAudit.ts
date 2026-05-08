import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { runShell } from "../exec.js";
import { repoRoot } from "../repo.js";

function summarizeAuditJson(path: string): string {
	if (!existsSync(path)) return `Audit report missing: ${path}`;
	try {
		const data = JSON.parse(readFileSync(path, "utf8"));
		const stats = data.statistics ?? {};
		const sev = stats.issues_by_severity ?? {};
		const meta = data.metadata ?? {};
		const errors = data.errors ?? [];
		const lines = [
			"Test audit summary",
			`findings: ${stats.issues_found ?? 0}`,
			`critical: ${sev.critical ?? 0}`,
			`high: ${sev.high ?? 0}`,
			`parser_mode: ${meta.parser_mode ?? "n/a"}`,
			`clang_attempted: ${meta.clang_attempted_count ?? 0}`,
			`clang_success: ${meta.clang_success_count ?? 0}`,
			`clang_fallback: ${meta.clang_fallback_count ?? 0}`,
			`parser_errors: ${errors.length}`,
			`report: ${path}`,
		];
		return lines.join("\n");
	} catch (err) {
		return `Could not parse audit report ${path}: ${String(err)}`;
	}
}

export function registerTestAudit(pi: ExtensionAPI): void {
	pi.registerCommand("test-audit", {
		description: "Run or summarize tooling/test-audit-validator: /test-audit [summary|clang]",
		handler: async (args, ctx) => {
			const root = repoRoot(ctx.cwd);
			const auditRoot = join(root, "tooling/test-audit-validator");
			const mode = args.trim() || "default";
			const autoReport = join(auditRoot, ".artifacts/test-audit/audit-auto.json");
			const clangReport = join(auditRoot, ".artifacts/test-audit/audit-clang.json");

			if (mode === "summary") {
				ctx.ui.notify(summarizeAuditJson(existsSync(autoReport) ? autoReport : clangReport), "info");
				return;
			}

			const target = mode === "clang" ? "audit-clang-gate" : "audit-gate";
			ctx.ui.setStatus("garazyk-test-audit", target);
			const result = await runShell(pi, auditRoot, `make ${target}`, 15 * 60 * 1000);
			ctx.ui.setStatus("garazyk-test-audit", undefined);
			const report = target === "audit-clang-gate" ? clangReport : autoReport;
			ctx.ui.notify(`${summarizeAuditJson(report)}\n\n${result.combined.split("\n").slice(-40).join("\n")}`, result.code === 0 ? "success" : "error");
		},
	});
}
