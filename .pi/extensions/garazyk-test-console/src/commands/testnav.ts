import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import { changedFiles } from "../parsers/git.js";
import { formatSuggestion, suggestTests } from "../maps/testSelection.js";
import { repoRoot } from "../repo.js";

async function pathsFor(pi: ExtensionAPI, cwd: string, args: string): Promise<string[]> {
	const explicit = args.trim().split(/\s+/).filter(Boolean).filter((a) => a !== "--changed");
	return explicit.length ? explicit : await changedFiles(pi, cwd);
}

export function registerTestNav(pi: ExtensionAPI): void {
	pi.registerCommand("testnav", {
		description: "Suggest focused Garazyk tests for changed files",
		handler: async (args, ctx) => {
			const root = repoRoot(ctx.cwd);
			const paths = await pathsFor(pi, root, args);
			ctx.ui.notify(formatSuggestion(paths, suggestTests(paths)), "info");
		},
	});

	pi.registerTool({
		name: "garazyk_test_suggest",
		label: "Garazyk Test Suggest",
		description: "Suggest focused Garazyk tests, scenarios, scripts, and fuzzers for changed files or explicit paths.",
		promptSnippet: "Suggest focused Garazyk tests for changed files",
		promptGuidelines: ["Use garazyk_test_suggest before running broad Garazyk test suites when source files changed."],
		parameters: Type.Object({
			paths: Type.Optional(Type.Array(Type.String(), { description: "Repository-relative paths. Defaults to current git diff." })),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const root = repoRoot(ctx.cwd);
			const paths = params.paths?.length ? params.paths : await changedFiles(pi, root);
			const text = formatSuggestion(paths, suggestTests(paths));
			return { content: [{ type: "text", text }], details: { paths, suggestion: suggestTests(paths) } };
		},
	});
}
