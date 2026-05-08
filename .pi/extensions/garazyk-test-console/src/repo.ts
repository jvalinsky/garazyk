import { existsSync } from "node:fs";
import { join, resolve } from "node:path";

export function repoRoot(cwd: string): string {
	let current = resolve(cwd);
	while (true) {
		if (existsSync(join(current, ".git")) || existsSync(join(current, "AGENTS.md"))) return current;
		const parent = resolve(current, "..");
		if (parent === current) return resolve(cwd);
		current = parent;
	}
}

export function shellQuote(value: string): string {
	return `'${value.replace(/'/g, `'\\''`)}'`;
}

export function shorten(text: string, max = 12000): string {
	if (text.length <= max) return text;
	return `${text.slice(0, max)}\n\n[truncated ${text.length - max} chars]`;
}

export function unique<T>(items: T[]): T[] {
	return Array.from(new Set(items));
}
