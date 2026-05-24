/** Log viewer island — fetches and renders ANSI-colored run logs with auto-scroll. @module LogViewer */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import { useRuntime } from "../runtime.ts";

/** Props for the LogViewer component. */
interface LogViewerProps {
  runId: string;
  status: string;
}

/** Interactive log viewer with ANSI rendering and auto-scroll. */
export default function LogViewer({ runId, status }: LogViewerProps) {
  const { state, dispatch } = useRuntime();
  const s = state.value;
  const logs = s.logs.textByRunId[runId] ?? "";
  const progress = s.runs.progressByRunId[runId];
  const isLive = progress?.running ?? status === "running";
  const scrollRef = useRef<HTMLPreElement>(null);
  const [ansiUpInstance, setAnsiUpInstance] = useState<any>(null);

  useEffect(() => {
    dispatch({ type: "runs/viewRun", runId });
  }, [runId]);

  useEffect(() => {
    import("ansi_up").then(({ AnsiUp }) => {
      setAnsiUpInstance(new AnsiUp());
    }).catch((e) => {
      console.error("Failed to load ansi_up:", e);
    });
  }, []);

  // Auto-scroll to bottom when logs update
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs]);

  const renderedLogs = useMemo(() => {
    if (!logs) return "";
    if (ansiUpInstance) {
      try {
        return ansiUpInstance.ansi_to_html(logs);
      } catch {
        return logs.replace(/</g, "&lt;").replace(/>/g, "&gt;");
      }
    }
    return logs.replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }, [logs, ansiUpInstance]);

  const loading = s.logs.fetchInFlight && !logs;

  return (
    <div style="margin-top: var(--space-xl);">
      <h2
        class="section-heading"
        style="display: flex; align-items: center; justify-content: space-between;"
      >
        System Logs
        {isLive && <span class="badge badge-warning">Live</span>}
      </h2>
      <pre
        ref={scrollRef}
        class="log-viewer"
        style="height: 500px; max-height: none; background: #000; color: #eee; border: 1px solid #333; overflow-x: auto; padding: 1rem;"
        dangerouslySetInnerHTML={{
          __html: renderedLogs ||
            (loading ? "Loading logs..." : "No logs available."),
        }}
      />
      <div style="font-size: var(--font-size-xs); color: var(--color-text-tertiary); margin-top: var(--space-xs); text-align: right;">
        Captured from scenario runner & docker containers
      </div>
    </div>
  );
}
