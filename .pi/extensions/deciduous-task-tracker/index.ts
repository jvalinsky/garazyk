import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { BorderedLoader, DynamicBorder } from "@mariozechner/pi-coding-agent";
import { Container, Key, SelectList, Text, matchesKey, truncateToWidth, wrapTextWithAnsi, type SelectItem } from "@mariozechner/pi-tui";
import { Type } from "typebox";

interface DeciduousNode {
	id: number;
	node_type: "goal" | "option" | "decision" | "action" | "outcome" | "observation";
	title: string;
	description?: string;
	status: "pending" | "active" | "completed" | "done" | "invalid" | "in_progress";
	created_at: string;
	updated_at: string;
}

interface DeciduousEdge {
	from: number;
	to: number;
	edge_type?: string;
	rationale?: string;
}

interface DeciduousGraph {
	nodes: DeciduousNode[];
	edges: DeciduousEdge[];
}

interface PulseSummary {
	total_nodes: number;
	total_edges: number;
	type_counts: Record<string, number>;
	status_counts: Record<string, number>;
	active_goals: number;
	pending_actions: number;
}

let currentGraph: DeciduousGraph | null = null;
let currentPulse: PulseSummary | null = null;
let refreshing = false;
let refreshPromise: Promise<void> | null = null;
let cachedStatus = "";

export default function (pi: ExtensionAPI) {
	async function runDeciduous(args: string[], cwd?: string): Promise<string> {
		const attempts = 4;
		for (let i = 0; i < attempts; i++) {
			const result = await pi.exec("deciduous", args, {
				cwd: cwd || process.cwd(),
				timeout: 12000,
			});
			if (result.code === 0) return result.stdout;

			const err = result.stderr || `deciduous exited with code ${result.code}`;
			const locked = /database is locked/i.test(err);
			if (!locked || i === attempts - 1) throw new Error(err);

			const delayMs = 120 * (i + 1);
			await new Promise((resolve) => setTimeout(resolve, delayMs));
		}
		throw new Error("deciduous failed");
	}

	function parsePulseSummary(output: string): PulseSummary {
		const summary: PulseSummary = {
			total_nodes: 0,
			total_edges: 0,
			type_counts: {},
			status_counts: {},
			active_goals: 0,
			pending_actions: 0,
		};

		for (const line of output.split("\n")) {
			if (line.includes("Nodes:")) {
				summary.total_nodes = Number(line.match(/Nodes:\s*(\d+)/)?.[1] || 0);
				summary.total_edges = Number(line.match(/Edges:\s*(\d+)/)?.[1] || 0);
			}
			if (line.includes("Types:")) {
				for (const match of line.matchAll(/(\w+)\((\d+)\)/g)) {
					summary.type_counts[match[1]] = Number(match[2]);
				}
			}
			if (line.includes("Status:")) {
				for (const match of line.matchAll(/(\w+)\((\d+)\)/g)) {
					summary.status_counts[match[1]] = Number(match[2]);
				}
			}
		}

		summary.active_goals = summary.status_counts.active || 0;
		summary.pending_actions = summary.status_counts.pending || 0;
		return summary;
	}

	function parseGraph(output: string): DeciduousGraph | null {
		try {
			const parsed = JSON.parse(output) as DeciduousGraph;
			if (!Array.isArray(parsed.nodes) || !Array.isArray(parsed.edges)) return null;
			return parsed;
		} catch {
			return null;
		}
	}

	function nodePrefix(node: DeciduousNode): string {
		const status = node.status === "active" || node.status === "in_progress" ? "●" : node.status === "completed" || node.status === "done" ? "✓" : "○";
		return `${status} #${node.id}`;
	}

	function updateIndicators(ctx: ExtensionContext): void {
		if (!currentPulse) {
			ctx.ui.setStatus("deciduous", refreshing ? "deciduous: refreshing…" : "deciduous: unavailable");
			return;
		}

		const status = `${currentPulse.total_nodes}n ${currentPulse.active_goals}g ${currentPulse.pending_actions}a`;
		if (status !== cachedStatus) {
			ctx.ui.setStatus("deciduous", ctx.ui.theme.fg("accent", `🌿 ${status}`));
			cachedStatus = status;
		}

		ctx.ui.setWidget("deciduous-work", (_tui, theme) => {
			const lines = [
				theme.fg("accent", theme.bold("Deciduous")),
				`${theme.fg("success", String(currentPulse?.active_goals || 0))} active goals`,
				`${theme.fg("warning", String(currentPulse?.pending_actions || 0))} pending actions`,
				theme.fg("dim", "/dt board • /dt refresh"),
			];
			return { render: () => lines, invalidate() {} };
		});
	}

	async function refresh(ctx: ExtensionContext): Promise<void> {
		if (refreshPromise) {
			await refreshPromise;
			return;
		}

		refreshPromise = (async () => {
			refreshing = true;
			updateIndicators(ctx);
			try {
				// Run sequentially to avoid SQLite lock contention between concurrent CLI calls.
				const graphOutput = await runDeciduous(["graph"], ctx.cwd);
				const pulseOutput = await runDeciduous(["pulse", "--summary"], ctx.cwd);
				currentGraph = parseGraph(graphOutput);
				currentPulse = parsePulseSummary(pulseOutput);
			} catch (err) {
				ctx.ui.notify(`Deciduous refresh failed: ${String(err).slice(0, 120)}`, "error");
			} finally {
				refreshing = false;
				updateIndicators(ctx);
			}
		})();

		try {
			await refreshPromise;
		} finally {
			refreshPromise = null;
		}
	}

	async function withLoader<T>(ctx: ExtensionContext, label: string, op: () => Promise<T>): Promise<T | null> {
		if (!ctx.hasUI) {
			return await op();
		}
		return await ctx.ui.custom<T | null>((tui, theme, _kb, done) => {
			const loader = new BorderedLoader(tui, theme, label);
			loader.onAbort = () => done(null);
			op()
				.then((value) => done(value))
				.catch(() => done(null));
			return loader;
		});
	}

	async function showBoard(ctx: ExtensionContext): Promise<void> {
		if (!currentGraph) await refresh(ctx);
		if (!currentGraph) {
			ctx.ui.notify("No graph data", "error");
			return;
		}

		const activeGoals = currentGraph.nodes.filter((n) => n.node_type === "goal" && (n.status === "active" || n.status === "in_progress"));
		const pendingActions = currentGraph.nodes.filter((n) => n.node_type === "action" && n.status === "pending");
		const allItems = [...activeGoals, ...pendingActions].slice(0, 40);

		if (allItems.length === 0) {
			ctx.ui.notify("No active goals or pending actions", "info");
			return;
		}

		const selectItems: SelectItem[] = allItems.map((n) => ({
			value: String(n.id),
			label: `${nodePrefix(n)} ${n.title}`,
			description: `${n.node_type} • ${n.status}`,
		}));

		const result = await ctx.ui.custom<string | null>((tui, theme, _kb, done) => {
			const container = new Container();
			container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
			container.addChild(new Text(theme.fg("accent", theme.bold("Deciduous Work Board")), 1, 0));

			const selectList = new SelectList(selectItems, Math.min(selectItems.length, 12), {
				selectedPrefix: (t) => theme.fg("accent", t),
				selectedText: (t) => theme.fg("accent", t),
				description: (t) => theme.fg("muted", t),
				scrollInfo: (t) => theme.fg("dim", t),
				noMatch: (t) => theme.fg("warning", t),
			});

			selectList.onSelect = (item) => done(item.value);
			selectList.onCancel = () => done(null);
			container.addChild(selectList);

			let details = "Select an item and press enter.";
			container.addChild(new Text("", 0, 0));
			const detailText = new Text(details, 1, 0);
			container.addChild(detailText);
			container.addChild(new Text(theme.fg("dim", "↑↓ navigate • enter details • esc close • r refresh"), 1, 0));
			container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));

			const updateDetails = (id?: string) => {
				const node = allItems.find((n) => String(n.id) === id);
				if (!node) return;
				details = `${nodePrefix(node)}\n${node.node_type} • ${node.status}\n\n${node.description || node.title}`;
				detailText.setText(wrapTextWithAnsi(truncateToWidth(details, 400), 70).join("\n"));
			};

			updateDetails(selectItems[0]?.value);

			return {
				render: (w: number) => container.render(w),
				invalidate: () => container.invalidate(),
				handleInput: (data: string) => {
					if (matchesKey(data, Key.escape)) {
						done(null);
						return;
					}
					if (matchesKey(data, "r")) {
						done("__refresh__");
						return;
					}
					selectList.handleInput(data);
					const idx = (selectList as any).selectedIndex as number | undefined;
					if (typeof idx === "number" && selectItems[idx]) updateDetails(selectItems[idx].value);
					tui.requestRender();
				},
			};
		}, {
			overlay: true,
			overlayOptions: {
				width: "85%",
				maxHeight: "85%",
				anchor: "center",
				visible: (w) => w >= 80,
			},
		});

		if (result === "__refresh__") {
			await refresh(ctx);
			await showBoard(ctx);
		}
	}

	pi.registerCommand("work", {
		description: "Start tracked work: /work <title>",
		handler: async (args, ctx) => {
			const title = args.trim();
			if (!title) {
				ctx.ui.notify("Usage: /work <title>", "error");
				return;
			}

			const prompt = await ctx.ui.editor("Goal description", title);
			if (!prompt?.trim()) return;

			const created = await withLoader(ctx, "Creating goal…", async () => {
				await runDeciduous(["add", "goal", title, "-c", "90", "-d", prompt], ctx.cwd);
				await refresh(ctx);
				return true;
			});

			if (created) ctx.ui.notify(`Goal added: ${title}`, "success");
			else ctx.ui.notify("Goal creation cancelled or failed", "warning");
		},
	});

	pi.registerCommand("dt", {
		description: "Deciduous: /dt [board|pulse|refresh|status|action <title>]",
		handler: async (args, ctx) => {
			const [sub, ...rest] = args.trim().split(/\s+/).filter(Boolean);
			const cmd = sub || "status";

			if (cmd === "refresh") {
				await refresh(ctx);
				ctx.ui.notify("Deciduous data refreshed", "success");
				return;
			}

			if (cmd === "action") {
				const title = rest.join(" ");
				if (!title) {
					ctx.ui.notify("Usage: /dt action <title>", "error");
					return;
				}
				await withLoader(ctx, "Adding action…", async () => {
					await runDeciduous(["add", "action", title, "-c", "85"], ctx.cwd);
					await refresh(ctx);
					return true;
				});
				ctx.ui.notify(`Action added: ${title}`, "success");
				return;
			}

			if (cmd === "pulse") {
				if (!currentPulse) await refresh(ctx);
				if (!currentPulse) return;
				ctx.ui.notify(`nodes:${currentPulse.total_nodes} edges:${currentPulse.total_edges} active:${currentPulse.active_goals} pending:${currentPulse.pending_actions}`, "info");
				return;
			}

			if (cmd === "board") {
				if (!ctx.hasUI) {
					ctx.ui.notify("/dt board requires interactive UI", "error");
					return;
				}
				await showBoard(ctx);
				return;
			}

			if (!currentPulse) await refresh(ctx);
			if (!currentPulse) {
				ctx.ui.notify("No Deciduous data available", "warning");
				return;
			}
			ctx.ui.notify(`Deciduous: ${currentPulse.total_nodes} nodes, ${currentPulse.active_goals} active goals, ${currentPulse.pending_actions} pending actions`, "info");
		},
	});

	pi.registerTool({
		name: "deciduous_add_node",
		label: "Add Deciduous Node",
		description: "Add a node to the decision graph",
		parameters: Type.Object({
			type: Type.Union([
				Type.Literal("goal"),
				Type.Literal("option"),
				Type.Literal("decision"),
				Type.Literal("action"),
				Type.Literal("outcome"),
				Type.Literal("observation"),
			]),
			title: Type.String(),
			description: Type.Optional(Type.String()),
			confidence: Type.Optional(Type.Number()),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const cmd = ["add", params.type, params.title];
			if (typeof params.confidence === "number") cmd.push("-c", String(params.confidence));
			if (params.description) cmd.push("-d", params.description);
			try {
				await runDeciduous(cmd, ctx.cwd);
				await refresh(ctx);
				return { content: [{ type: "text", text: `Added ${params.type}: ${params.title}` }] };
			} catch (err) {
				return { content: [{ type: "text", text: `Failed: ${String(err)}` }] };
			}
		},
	});

	pi.registerTool({
		name: "deciduous_show_active",
		label: "Show Active Work",
		description: "Show active goals and actions",
		parameters: Type.Object({}),
		async execute(_toolCallId, _params, _signal, _onUpdate, ctx) {
			if (!currentGraph) await refresh(ctx);
			if (!currentGraph) return { content: [{ type: "text", text: "No graph data available" }] };

			const goals = currentGraph.nodes.filter((n) => n.node_type === "goal" && (n.status === "active" || n.status === "in_progress"));
			const actions = currentGraph.nodes.filter((n) => n.node_type === "action" && (n.status === "active" || n.status === "in_progress" || n.status === "pending"));
			const lines = [
				`Active goals (${goals.length})`,
				...goals.slice(0, 10).map((n) => `- #${n.id} ${n.title}`),
				"",
				`Active/pending actions (${actions.length})`,
				...actions.slice(0, 15).map((n) => `- #${n.id} ${n.title}`),
			];
			return { content: [{ type: "text", text: lines.join("\n") }] };
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		await refresh(ctx);
	});

	pi.on("session_tree", async (_event, ctx) => {
		await refresh(ctx);
	});
}
