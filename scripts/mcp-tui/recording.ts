import { CastRecorder } from "@garazyk/tui/testing";
import type { VirtualTuiHarness } from "@garazyk/tui/testing";
import { join } from "@std/path";
import { buildExportHtml } from "../scenario-dashboard/lib/export_html.ts";

export interface RecordingHandle {
  title: string;
  outputDir: string;
  recorder: CastRecorder;
  startedAt: number;
}

export function startRecording(
  harness: VirtualTuiHarness,
  title: string | undefined,
  outputDir: string | undefined,
  baseDir: string,
): RecordingHandle {
  const startedAt = Date.now();
  const dir = outputDir ??
    `scripts/scenarios/reports/tui-capture/mcp-${startedAt}`;
  const absDir = join(baseDir, dir);

  Deno.mkdirSync(absDir, { recursive: true });

  const recorder = new CastRecorder(harness, {
    title: title ?? "Garazyk MCP TUI Capture",
    minFrameInterval: 0.03,
  });
  harness.attachRecorder(recorder);

  return {
    title: title ?? "Garazyk MCP TUI Capture",
    outputDir: absDir,
    recorder,
    startedAt,
  };
}

export async function stopRecording(
  handle: RecordingHandle,
  harness: VirtualTuiHarness,
): Promise<{ castPath: string; htmlPath: string }> {
  const { recorder, outputDir } = handle;

  await recorder.close();
  harness.detachRecorder(recorder);
  const castContent = recorder.exportAsciicast();

  const castPath = join(outputDir, "dashboard.cast");
  await Deno.writeTextFile(castPath, castContent);

  const html = buildExportHtml({
    runId: "mcp-capture",
    castContent,
    events: [],
    startedAt: handle.startedAt,
  });

  const htmlPath = join(outputDir, "index.html");
  await Deno.writeTextFile(htmlPath, html);

  return { castPath, htmlPath };
}
