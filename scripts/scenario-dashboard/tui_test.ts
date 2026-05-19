import { assertStringIncludes } from "jsr:@std/assert";
import { renderTuiFrame } from "./tui.ts";

Deno.test("renderTuiFrame includes scenario and run summaries", () => {
  const frame = renderTuiFrame({
    rootDir: "/tmp/garazyk",
    generatedAt: 0,
    services: [{
      name: "pds",
      label: "PDS",
      url: "http://localhost:2583",
      port: 2583,
      status: "running",
      healthy: true,
    }],
    activeRun: null,
    recentRuns: [{
      id: "run-1",
      startedAt: 0,
      status: "completed",
      totalScenarios: 2,
      passed: 2,
      failed: 0,
      skipped: 0,
    }],
    scenarioCount: 63,
    topologies: ["garazyk-default"],
  });

  assertStringIncludes(frame, "Garazyk Scenario Dashboard");
  assertStringIncludes(frame, "Scenarios");
  assertStringIncludes(frame, "63");
  assertStringIncludes(frame, "run-1");
});
