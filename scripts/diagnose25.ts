// Reproduce the exact import path used by run_scenarios.ts
const path = "/Users/jack/Software/garazyk/scripts/scenarios/scenarios/25_firehose_fanout_scale.ts";
console.log("importing:", path);
const module = await import(`file://${path}`);
console.log("imported, module keys:", Object.keys(module));
console.log("has run:", typeof module.run);

console.log("=== calling module.run() ===");
const t0 = performance.now();
const result = await module.run();
const t1 = performance.now();
console.log(`=== run() completed in ${((t1 - t0) / 1000).toFixed(1)}s ===`);
console.log(result.summary());
Deno.exit(0);
