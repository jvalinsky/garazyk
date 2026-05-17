let inst = await Deno.readTextFile("packages/scenario-runner/instrumentation.ts");

// OperationStats methods
inst = inst.replace(/get min\(\) \{/g, "get min(): number {");
inst = inst.replace(/get max\(\) \{/g, "get max(): number {");
inst = inst.replace(/get mean\(\) \{/g, "get mean(): number {");
inst = inst.replace(/percentile\(p: number\) \{/g, "percentile(p: number): number {");
inst = inst.replace(/get p50\(\) \{/g, "get p50(): number {");
inst = inst.replace(/get p95\(\) \{/g, "get p95(): number {");
inst = inst.replace(/get p99\(\) \{/g, "get p99(): number {");
inst = inst.replace(/get totalMs\(\) \{/g, "get totalMs(): number {");
inst = inst.replace(/toDict\(\) \{/g, "toDict(): Record<string, any> {");

// DurationTracker methods
inst = inst.replace(/getStats\(name: string\) \{/g, "getStats(name: string): OperationStats {");
inst = inst.replace(/getAllStats\(\) \{/g, "getAllStats(): Record<string, OperationStats> {");

// stop methods and others
inst = inst.replace(/async stop\(\) \{/g, "async stop(): Promise<void> {");
inst = inst.replace(/getTimeSeries\(\) \{/g, "getTimeSeries(): any[] {");

await Deno.writeTextFile("packages/scenario-runner/instrumentation.ts", inst);
console.log("Fixed instrumentation.ts");
