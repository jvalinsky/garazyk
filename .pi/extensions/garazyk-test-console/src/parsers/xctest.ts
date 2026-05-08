export interface XCTestFailure {
	test?: string;
	file?: string;
	line?: number;
	message: string;
}

export interface XCTestRunSummary {
	testsRun?: number;
	failures?: number;
	skippedClasses: string[];
	failedAssertions: XCTestFailure[];
	slowClasses: Array<{ className: string; seconds: number; count: number }>;
	slowMethods: Array<{ className: string; method: string; seconds: number }>;
	registrationMissing: string[];
	registrationStale: string[];
	registrationPassed: boolean;
}

export function parseXCTestOutput(text: string): XCTestRunSummary {
	const summary: XCTestRunSummary = {
		skippedClasses: [],
		failedAssertions: [],
		slowClasses: [],
		slowMethods: [],
		registrationMissing: [],
		registrationStale: [],
		registrationPassed: /Registration audit passed/.test(text),
	};

	const testsRun = text.match(/Tests run:\s*(\d+)/);
	if (testsRun) summary.testsRun = Number(testsRun[1]);
	const failures = text.match(/Failures:\s*(\d+)/);
	if (failures) summary.failures = Number(failures[1]);

	for (const match of text.matchAll(/FAIL:\s*([^\n]+?)\s+at\s+([^:]+):(\d+):\s*([^\n]+)/g)) {
		summary.failedAssertions.push({ test: match[1].trim(), file: match[2], line: Number(match[3]), message: match[4].trim() });
	}

	let skipped = false;
	for (const line of text.split(/\r?\n/)) {
		if (/Skipped gated test classes/.test(line)) {
			skipped = true;
			continue;
		}
		if (skipped) {
			const m = line.match(/^\s+([^\s].*\))\s*$/);
			if (m) summary.skippedClasses.push(m[1]);
			else if (line.trim() === "") skipped = false;
		}
	}

	const classSection = text.split("Class timings:")[1]?.split("Slowest test methods:")[0] ?? "";
	for (const match of classSection.matchAll(/^\s*([0-9.]+)s\s+(\d+)\s+([A-Za-z0-9_]+)\s*$/gm)) {
		summary.slowClasses.push({ seconds: Number(match[1]), count: Number(match[2]), className: match[3] });
	}

	const methodSection = text.split("Slowest test methods:")[1] ?? "";
	for (const match of methodSection.matchAll(/^\s*([0-9.]+)s\s+([A-Za-z0-9_]+)\/([^\s]+)\s*$/gm)) {
		summary.slowMethods.push({ seconds: Number(match[1]), className: match[2], method: match[3] });
	}

	const missingSection = text.split("Runtime test classes missing from runner")[1]?.split("Runner classes not present at runtime")[0] ?? "";
	for (const match of missingSection.matchAll(/^\s+([A-Za-z0-9_]+)\s*$/gm)) summary.registrationMissing.push(match[1]);

	const staleSection = text.split("Runner classes not present at runtime")[1] ?? "";
	for (const match of staleSection.matchAll(/^\s+([A-Za-z0-9_]+)\s*$/gm)) summary.registrationStale.push(match[1]);

	return summary;
}

export function formatXCTestSummary(title: string, exitCode: number, summary: XCTestRunSummary, logPath?: string): string {
	const status = exitCode === 0 ? "PASS" : "FAIL";
	const lines = [`${title}: ${status}`];
	if (summary.testsRun !== undefined) lines.push(`Tests run: ${summary.testsRun}`);
	if (summary.failures !== undefined) lines.push(`Failures: ${summary.failures}`);
	if (summary.registrationPassed) lines.push("Registration audit: passed");
	if (summary.registrationMissing.length) lines.push(`Missing registrations: ${summary.registrationMissing.join(", ")}`);
	if (summary.registrationStale.length) lines.push(`Stale registrations: ${summary.registrationStale.join(", ")}`);
	if (summary.failedAssertions.length) {
		lines.push("", "Failed assertions:");
		for (const f of summary.failedAssertions.slice(0, 12)) {
			lines.push(`- ${f.test ?? "test"}${f.file ? ` at ${f.file}:${f.line}` : ""}: ${f.message}`);
		}
	}
	if (summary.skippedClasses.length) {
		lines.push("", `Skipped gated classes (${summary.skippedClasses.length}):`);
		for (const s of summary.skippedClasses.slice(0, 10)) lines.push(`- ${s}`);
	}
	if (summary.slowMethods.length) {
		lines.push("", "Slowest methods:");
		for (const m of summary.slowMethods.slice(0, 8)) lines.push(`- ${m.seconds.toFixed(3)}s ${m.className}/${m.method}`);
	}
	if (logPath) lines.push("", `Log: ${logPath}`);
	return lines.join("\n");
}
