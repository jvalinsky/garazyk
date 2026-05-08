import { readFileSync } from "node:fs";
import { join } from "node:path";

export interface TestMainInfo {
	registeredClasses: string[];
	integrationClasses: string[];
	socketClasses: string[];
}

function extractStringArray(source: string, marker: string): string[] {
	const markerIndex = source.indexOf(marker);
	if (markerIndex < 0) return [];
	const start = source.indexOf("@[", markerIndex);
	if (start < 0) return [];
	let depth = 0;
	let end = -1;
	for (let i = start; i < source.length; i++) {
		const pair = source.slice(i, i + 2);
		if (pair === "@[") {
			depth++;
			i++;
			continue;
		}
		if (source[i] === "]") {
			depth--;
			if (depth === 0) {
				end = i;
				break;
			}
		}
	}
	if (end < 0) return [];
	const body = source.slice(start, end + 1);
	return Array.from(body.matchAll(/@"([^"]+)"/g)).map((m) => m[1]);
}

export function readTestMain(repoRoot: string): TestMainInfo {
	const path = join(repoRoot, "Garazyk/Tests/test_main.m");
	const source = readFileSync(path, "utf8");
	return {
		registeredClasses: extractStringArray(source, "NSArray *testClasses"),
		integrationClasses: extractStringArray(source, "PDSIntegrationTestClasses"),
		socketClasses: extractStringArray(source, "PDSSocketTestClasses"),
	};
}

export function formatTestClassList(info: TestMainInfo): string {
	const lines = [`Registered XCTest classes: ${info.registeredClasses.length}`, ""];
	for (const className of info.registeredClasses) {
		const tags: string[] = [];
		if (info.integrationClasses.includes(className)) tags.push("integration");
		if (info.socketClasses.includes(className)) tags.push("socket");
		lines.push(`- ${className}${tags.length ? ` (${tags.join(", ")})` : ""}`);
	}
	return lines.join("\n");
}
