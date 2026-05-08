import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { runShell } from "../exec.js";
import { repoRoot } from "../repo.js";

const services = [
	{ key: "plc", label: "PLC", url: "http://127.0.0.1:2582/_health", log: "/tmp/plc.log" },
	{ key: "pds", label: "PDS", url: "http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer", log: "/tmp/pds.log" },
	{ key: "relay", label: "Relay", url: "http://127.0.0.1:2584/api/relay/health", log: "/tmp/relay.log" },
	{ key: "appview", label: "AppView", url: "http://127.0.0.1:3200/_health", log: "/tmp/appview.log" },
	{ key: "pds2", label: "PDS2", url: "http://127.0.0.1:2585/xrpc/com.atproto.server.describeServer", log: "/tmp/pds2.log" },
];

async function serviceStatus(pi: ExtensionAPI, cwd: string): Promise<Array<{ label: string; ok: boolean; url: string }>> {
	const results = [];
	for (const service of services) {
		const result = await runShell(pi, cwd, `curl -fsS --max-time 2 ${service.url} >/dev/null`, 5000);
		results.push({ label: service.label, ok: result.code === 0, url: service.url });
	}
	return results;
}

function formatStatus(items: Array<{ label: string; ok: boolean; url: string }>): string {
	return ["ATProto service health", "", ...items.map((i) => `${i.ok ? "PASS" : "FAIL"} ${i.label} — ${i.url}`)].join("\n");
}

export function registerServices(pi: ExtensionAPI): void {
	pi.registerCommand("services", {
		description: "Check local ATProto service health or logs: /services [logs <pds|plc|relay|appview|pds2>|teardown]",
		handler: async (args, ctx) => {
			const root = repoRoot(ctx.cwd);
			const tokens = args.trim().split(/\s+/).filter(Boolean);
			if (tokens[0] === "logs") {
				const key = tokens[1] ?? "pds";
				const service = services.find((s) => s.key === key);
				if (!service) {
					ctx.ui.notify(`Unknown service: ${key}`, "error");
					return;
				}
				const result = await runShell(pi, root, `if [ -f ${service.log} ]; then tail -120 ${service.log}; else echo 'No binary-mode log at ${service.log}'; fi`, 10000);
				ctx.ui.notify(result.combined, result.code === 0 ? "info" : "error");
				return;
			}
			if (tokens[0] === "teardown") {
				const binary = tokens.includes("--binary") ? " --binary" : "";
				const result = await runShell(pi, root, `./scripts/scenarios/setup_local_network.sh --teardown${binary}`, 120000);
				ctx.ui.setStatus("garazyk-services", undefined);
				ctx.ui.notify(result.combined || "Teardown complete", result.code === 0 ? "success" : "error");
				return;
			}
			const items = await serviceStatus(pi, root);
			const compact = items.map((i) => `${i.label}:${i.ok ? "✓" : "×"}`).join(" ");
			ctx.ui.setStatus("garazyk-services", compact);
			ctx.ui.notify(formatStatus(items), items.some((i) => !i.ok) ? "warning" : "success");
		},
	});
}
