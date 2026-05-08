import { unique } from "../repo.js";

export interface TestSuggestion {
	changedAreas: string[];
	tests: string[];
	env: string[];
	scenarios: string[];
	scripts: string[];
	fuzzers: string[];
	rationale: string[];
}

interface Rule {
	name: string;
	match: RegExp;
	tests?: string[];
	env?: string[];
	scenarios?: string[];
	scripts?: string[];
	fuzzers?: string[];
	rationale: string;
}

const rules: Rule[] = [
	{ name: "Auth/OAuth", match: /^Garazyk\/Sources\/Auth\//, tests: ["OAuth2HandlerTests", "OAuthSessionTests", "OAuthDPoPTests", "JWTTests"], scenarios: ["08"], fuzzers: ["fuzz_auth", "fuzz_jwt", "fuzz_dpop"], rationale: "Auth changes should exercise token/session, DPoP/JWT, and OAuth scenario coverage." },
	{ name: "Network/XRPC", match: /^Garazyk\/Sources\/Network\//, tests: ["HttpRouterTests", "HttpRequestParsingTests", "HttpProtocolDriverTests", "PDSHttpServerBuilderTests"], env: ["PDS_RUN_SOCKET_TESTS=1"], fuzzers: ["fuzz_http", "fuzz_xrpc"], rationale: "Network changes affect parser/router behavior and may require socket-gated tests." },
	{ name: "Database", match: /^Garazyk\/Sources\/Database\//, tests: ["DatabasePoolTests", "PDSDatabaseIntegrationTests", "MultiTenantDatabaseTests"], env: ["PDS_RUN_INTEGRATION_TESTS=1"], fuzzers: ["fuzz_sqlite"], rationale: "Database changes need pool/migration/integration checks." },
	{ name: "Repository/MST", match: /^Garazyk\/Sources\/(Repository|Core\/Repositories)\//, tests: ["RepoCommitTests", "MSTInteropTests", "CommitChainTests"], scenarios: ["03", "09"], fuzzers: ["fuzz_mst", "fuzz_cbor"], rationale: "Repository changes affect records, commit chains, MST/CAR, and firehose-visible mutations." },
	{ name: "Blob", match: /^Garazyk\/Sources\/Blob\//, tests: ["BlobStorageTests", "BlobXrpcTests", "MimeTypeValidatorTests"], scenarios: ["07"], fuzzers: ["fuzz_mime", "fuzz_blob"], rationale: "Blob changes need storage, XRPC, MIME, and upload scenario checks." },
	{ name: "Sync/Federation", match: /^Garazyk\/Sources\/(Sync|Federation)\//, tests: ["FirehoseIntegrationTests", "RelayIntegrationTests", "FederationClientTests"], env: ["PDS_RUN_INTEGRATION_TESTS=1"], scenarios: ["05", "09"], rationale: "Sync/federation changes need relay, firehose, and multi-PDS scenario checks." },
	{ name: "AppView", match: /^Garazyk\/Sources\/AppView\//, tests: ["AppViewServiceTests", "AppViewIngestEngineTests", "AppViewBackfillTests"], scenarios: ["02", "03", "09"], rationale: "AppView changes should exercise ingest, backfill, graph/feed, and firehose paths." },
	{ name: "Admin UI", match: /^Garazyk\/Sources\/(AdminUIServer|.*\/Assets)\//, tests: ["UIServerRuntimeTests", "UIBackendClientTests", "UILabIntegrationTests"], scripts: ["scripts/test/check_ui_design_system.sh"], rationale: "UI assets need server/runtime tests plus design-system checks." },
	{ name: "Tests", match: /^Garazyk\/Tests\//, scripts: ["PDS_TEST_REGISTRATION_AUDIT=1 ./build/tests/AllTests"], rationale: "Test changes should run the registration audit to catch invisible tests." },
	{ name: "Scenario scripts", match: /^scripts\/scenarios\//, scenarios: ["changed-or-all"], rationale: "Scenario harness changes should run affected scenarios or the full scenario set." },
	{ name: "Fuzzing", match: /^fuzzing\//, scripts: ["/fuzz suggest"], rationale: "Fuzzing changes should build/run the affected fuzzer and check crash regressions." },
];

export function suggestTests(paths: string[]): TestSuggestion {
	const out: TestSuggestion = { changedAreas: [], tests: [], env: [], scenarios: [], scripts: [], fuzzers: [], rationale: [] };
	for (const path of paths) {
		for (const rule of rules) {
			if (!rule.match.test(path)) continue;
			out.changedAreas.push(rule.name);
			out.tests.push(...(rule.tests ?? []));
			out.env.push(...(rule.env ?? []));
			out.scenarios.push(...(rule.scenarios ?? []));
			out.scripts.push(...(rule.scripts ?? []));
			out.fuzzers.push(...(rule.fuzzers ?? []));
			out.rationale.push(`${rule.name}: ${rule.rationale}`);
		}
	}
	out.changedAreas = unique(out.changedAreas);
	out.tests = unique(out.tests);
	out.env = unique(out.env);
	out.scenarios = unique(out.scenarios);
	out.scripts = unique(out.scripts);
	out.fuzzers = unique(out.fuzzers);
	out.rationale = unique(out.rationale);
	return out;
}

export function formatSuggestion(paths: string[], suggestion: TestSuggestion): string {
	const lines: string[] = ["Focused test plan", ""];
	if (paths.length === 0) {
		lines.push("No changed files detected. Pass paths explicitly or run from a branch with changes.");
		return lines.join("\n");
	}
	lines.push("Changed files:");
	for (const path of paths.slice(0, 25)) lines.push(`- ${path}`);
	if (paths.length > 25) lines.push(`- ... ${paths.length - 25} more`);
	lines.push("");
	if (suggestion.changedAreas.length) lines.push(`Changed areas: ${suggestion.changedAreas.join(", ")}`, "");
	if (suggestion.tests.length) {
		const env = suggestion.env.length ? `${suggestion.env.join(" ")} ` : "";
		lines.push("Recommended XCTest:", `- ${env}./build/tests/AllTests -XCTest ${suggestion.tests.join(",")}`, "");
	}
	if (suggestion.scenarios.length) lines.push("Recommended scenarios:", `- python3 scripts/scenarios/run_scenario.py ${suggestion.scenarios.join(" ")}`, "");
	if (suggestion.scripts.length) lines.push("Other checks:", ...suggestion.scripts.map((s) => `- ${s}`), "");
	if (suggestion.fuzzers.length) lines.push("Suggested fuzzers:", `- ${suggestion.fuzzers.join(", ")}`, "");
	if (suggestion.rationale.length) lines.push("Rationale:", ...suggestion.rationale.map((r) => `- ${r}`));
	if (!suggestion.changedAreas.length) lines.push("No mapping matched. Run closest subsystem tests, then ./build/tests/AllTests before pushing.");
	return lines.join("\n");
}
