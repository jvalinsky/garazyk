import { readFile } from "node:fs/promises";
import { createObjcKernel } from "./tests/objc-kernel-test-harness.mjs";

const wasmPath = process.argv[2] || "result/wasm/kernel.wasm";
const notebookPath = process.argv[3] || "demo/01-hello-objc.ipynb";

async function main() {
  const raw = await readFile(notebookPath, "utf-8");
  const nb = JSON.parse(raw);
  const kernel = await createObjcKernel(wasmPath);

  let cellNum = 0;
  for (const cell of nb.cells) {
    if (cell.cell_type !== "code") continue;
    const source = Array.isArray(cell.source) ? cell.source.join("") : cell.source;
    if (!source.trim()) continue;

    cellNum++;
    const label = source.split("\n")[0].slice(0, 60);
    process.stdout.write(`[${cellNum}] ${label}... `);

    const result = kernel.execute(source);
    if (result.status !== "ok") {
      console.log(`FAIL (${result.status})`);
      for (const s of result.streams || []) {
        if (s.name === "stderr") process.stderr.write(s.text);
      }
      continue;
    }

    const stdout = (result.streams || [])
      .filter((s) => s.name === "stdout")
      .map((s) => s.text)
      .join("")
      .trim();

    if (stdout) {
      console.log(`OK`);
      for (const line of stdout.split("\n")) console.log(`  | ${line}`);
    } else {
      console.log(`OK (no output)`);
    }
  }

  console.log(`\nExecuted ${cellNum} code cells from ${notebookPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
