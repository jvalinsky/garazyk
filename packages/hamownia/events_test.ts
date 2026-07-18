/** Tests for hamownia/events.ts — HumanReadableSink and MultiSink. @module events_test */

import { assertEquals } from "@std/assert";
import { MultiSink } from "./events.ts";
import type {
  RunFinishedEvent,
  RunProgressEvent,
  RunStartedEvent,
  ScenarioCompletedEvent,
  ScenarioRunEvent,
  ScenarioRunEventSink,
  ScenarioStartedEvent,
  ServiceFailureEvent,
} from "./events.ts";

// ── Capture Sink ────────────────────────────────────────────────────────

/** Minimal sink that records emitted events for assertion. */
class CaptureSink implements ScenarioRunEventSink {
  events: ScenarioRunEvent[] = [];
  emit(event: ScenarioRunEvent): void {
    this.events.push(event);
  }
}

// ── MultiSink ───────────────────────────────────────────────────────────

Deno.test("MultiSink: fans out to two children", () => {
  const a = new CaptureSink();
  const b = new CaptureSink();
  const multi = new MultiSink([a, b]);

  const ev: RunStartedEvent = {
    type: "run_start",
    runId: "r1",
    scenarioIds: ["01"],
    total: 1,
    timestamp: 1000,
  };
  multi.emit(ev);

  assertEquals(a.events.length, 1);
  assertEquals(b.events.length, 1);
  assertEquals(a.events[0], ev);
  assertEquals(b.events[0], ev);
});

Deno.test("MultiSink: fans out to three children", () => {
  const sinks = [new CaptureSink(), new CaptureSink(), new CaptureSink()];
  const multi = new MultiSink(sinks);

  const ev: ScenarioStartedEvent = {
    type: "scenario_start",
    scenarioId: "01",
    name: "test",
    index: 0,
    total: 1,
    timestamp: 2000,
  };
  multi.emit(ev);

  for (const s of sinks) {
    assertEquals(s.events.length, 1);
    assertEquals(s.events[0], ev);
  }
});

Deno.test("MultiSink: emits multiple events in order", () => {
  const sink = new CaptureSink();
  const multi = new MultiSink([sink]);

  const runStart: RunStartedEvent = {
    type: "run_start",
    runId: "r1",
    scenarioIds: ["01"],
    total: 1,
    timestamp: 1000,
  };
  const scenarioStart: ScenarioStartedEvent = {
    type: "scenario_start",
    scenarioId: "01",
    name: "lifecycle",
    index: 0,
    total: 1,
    timestamp: 1100,
  };
  const scenarioComplete: ScenarioCompletedEvent = {
    type: "scenario_complete",
    scenarioId: "01",
    name: "lifecycle",
    ok: true,
    passed: 2,
    failed: 0,
    skipped: 0,
    durationS: 1.5,
    summaryText: "passed",
    timestamp: 1600,
  };
  const runFinished: RunFinishedEvent = {
    type: "run_finished",
    runId: "r1",
    ok: true,
    totalPassed: 2,
    totalFailed: 0,
    totalSkipped: 0,
    reportsDir: "/tmp",
    crashedContainer: false,
    timestamp: 2000,
  };

  multi.emit(runStart);
  multi.emit(scenarioStart);
  multi.emit(scenarioComplete);
  multi.emit(runFinished);

  assertEquals(sink.events.length, 4);
  assertEquals(sink.events[0].type, "run_start");
  assertEquals(sink.events[1].type, "scenario_start");
  assertEquals(sink.events[2].type, "scenario_complete");
  assertEquals(sink.events[3].type, "run_finished");
});

Deno.test("MultiSink: close propagates to children", async () => {
  let closedA = false;
  let closedB = false;

  const sinkA: ScenarioRunEventSink = {
    emit: () => {},
    close: () => { closedA = true; },
  };
  const sinkB: ScenarioRunEventSink = {
    emit: () => {},
    close: () => { closedB = true; },
  };

  const multi = new MultiSink([sinkA, sinkB]);
  await multi.close();

  assertEquals(closedA, true);
  assertEquals(closedB, true);
});

Deno.test("MultiSink: close handles async close methods", async () => {
  let resolved = false;

  const sink: ScenarioRunEventSink = {
    emit: () => {},
    close: async () => {
      await new Promise((r) => setTimeout(r, 10));
      resolved = true;
    },
  };

  const multi = new MultiSink([sink]);
  await multi.close();

  assertEquals(resolved, true);
});

Deno.test("MultiSink: close tolerates children without close method", async () => {
  const sink: ScenarioRunEventSink = { emit: () => {} };
  const multi = new MultiSink([sink]);
  await multi.close();
});

Deno.test("MultiSink: service_failure event fans out correctly", () => {
  const a = new CaptureSink();
  const b = new CaptureSink();
  const multi = new MultiSink([a, b]);

  const ev: ServiceFailureEvent = {
    type: "service_failure",
    message: "PDS unhealthy",
    source: "health_check",
    timestamp: 3000,
  };
  multi.emit(ev);

  assertEquals(a.events.length, 1);
  assertEquals(b.events.length, 1);
  assertEquals((a.events[0] as ServiceFailureEvent).message, "PDS unhealthy");
  assertEquals((b.events[0] as ServiceFailureEvent).source, "health_check");
});

Deno.test("MultiSink: run_progress with running=false fans out", () => {
  const sink = new CaptureSink();
  const multi = new MultiSink([sink]);

  const ev: RunProgressEvent = {
    type: "run_progress",
    completed: 5,
    total: 5,
    currentScenarioId: null,
    currentScenarioName: null,
    running: false,
    timestamp: 4000,
  };
  multi.emit(ev);

  assertEquals(sink.events.length, 1);
  const emitted = sink.events[0] as RunProgressEvent;
  assertEquals(emitted.running, false);
  assertEquals(emitted.completed, 5);
});
