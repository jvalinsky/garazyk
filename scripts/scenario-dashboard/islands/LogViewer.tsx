/** Log viewer island — fetches and renders ANSI-colored run logs with auto-scroll. @module LogViewer */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import { useRuntime } from "../runtime.ts";
import { sanitizeLogHtml } from "../utils/log_html.ts";

/** Props for the LogViewer component. */
interface LogViewerProps {
  runId: string;
  status: string;
  /** Server-known log file path, if any. */
  logPath?: string | null;
  /** Scroll to approximate position 0–1 when timeline seeks. */
  scrollRatio?: number;
  /** Scroll to a zero-based log line index (preferred over scrollRatio). */
  scrollToLine?: number;
}

const STICKY_SCROLL_THRESHOLD_PX = 48;

/** Interactive log viewer with ANSI rendering, filter, and copy. */
export default function LogViewer(
  { runId, status, logPath, scrollRatio, scrollToLine }: LogViewerProps,
) {
  const { state, dispatch } = useRuntime();
  const s = state.value;
  const logs = s.logs.textByRunId[runId] ?? "";
  const logError = s.logs.lastErrorByRunId[runId];
  const progress = s.runs.progressByRunId[runId];
  const isLive = progress?.running ?? status === "running";
  const scrollRef = useRef<HTMLPreElement>(null);
  const stickToBottomRef = useRef(true);
  const [ansiUpInstance, setAnsiUpInstance] = useState<
    { ansi_to_html: (text: string) => string } | null
  >(null);
  const [filter, setFilter] = useState("");
  const [copyState, setCopyState] = useState<"idle" | "done" | "failed">(
    "idle",
  );

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

  const filteredLogs = useMemo(() => {
    if (!filter.trim()) return logs;
    const term = filter.trim().toLowerCase();
    return logs
      .split("\n")
      .filter((line) => line.toLowerCase().includes(term))
      .join("\n");
  }, [logs, filter]);

  const renderedLogs = useMemo(() => {
    if (!filteredLogs) return "";
    if (ansiUpInstance) {
      try {
        return sanitizeLogHtml(ansiUpInstance.ansi_to_html(filteredLogs));
      } catch {
        return filteredLogs.replace(/</g, "&lt;").replace(/>/g, "&gt;");
      }
    }
    return filteredLogs.replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }, [filteredLogs, ansiUpInstance]);

  useEffect(() => {
    if (!stickToBottomRef.current || !scrollRef.current) return;
    scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [renderedLogs]);

  useEffect(() => {
    if (scrollRatio === undefined || !scrollRef.current) return;
    const el = scrollRef.current;
    const max = el.scrollHeight - el.clientHeight;
    el.scrollTop = Math.round(max * Math.min(1, Math.max(0, scrollRatio)));
    stickToBottomRef.current = scrollRatio >= 0.95;
  }, [scrollRatio]);

  useEffect(() => {
    if (scrollToLine === undefined || !scrollRef.current || !logs) return;
    const el = scrollRef.current;
    const lineCount = logs.split("\n").length;
    if (lineCount <= 1) return;
    const lineHeight = el.scrollHeight / lineCount;
    el.scrollTop = Math.round(scrollToLine * lineHeight);
    stickToBottomRef.current = scrollToLine >= lineCount - 2;
  }, [scrollToLine, logs]);

  function handleScroll() {
    const el = scrollRef.current;
    if (!el) return;
    const distance = el.scrollHeight - el.scrollTop - el.clientHeight;
    stickToBottomRef.current = distance <= STICKY_SCROLL_THRESHOLD_PX;
  }

  function jumpToLatest() {
    const el = scrollRef.current;
    if (!el) return;
    stickToBottomRef.current = true;
    el.scrollTop = el.scrollHeight;
  }

  async function copyLogs() {
    if (!logs) return;
    try {
      await navigator.clipboard.writeText(logs);
      setCopyState("done");
      setTimeout(() => setCopyState("idle"), 2000);
    } catch {
      setCopyState("failed");
      setTimeout(() => setCopyState("idle"), 2000);
    }
  }

  const loading = s.logs.fetchInFlight && s.logs.inFlightRunId === runId &&
    !logs;
  const hasContent = filteredLogs.trim().length > 0;

  function emptyMessage(): { title: string; detail: string } {
    if (loading) {
      return {
        title: "Loading logs",
        detail: "Fetching output from the scenario runner and containers.",
      };
    }
    if (logError) {
      return {
        title: "Logs not ready",
        detail: logError,
      };
    }
    if (!logPath) {
      return {
        title: "No log file for this run",
        detail:
          "This run did not record a log path. Use the failure triage panel above for the failed step, open the scenario detail page, or check service output in your terminal.",
      };
    }
    if (isLive) {
      return {
        title: "Waiting for log output",
        detail:
          `The runner is still writing to ${logPath}. Output appears here as lines are captured.`,
      };
    }
    return {
      title: "Log file is empty or missing",
      detail:
        `Expected log at ${logPath}. The file may not have been created, or the run ended before logging started. Check the failed scenario step detail and network service health.`,
    };
  }

  const empty = !hasContent ? emptyMessage() : null;

  return (
    <div id="system-logs" class="log-viewer-panel">
      <div class="log-viewer-header">
        <h2 class="section-heading log-viewer-title">
          System Logs
          {isLive && <span class="badge badge-warning">Live</span>}
        </h2>
        <div class="log-viewer-tools">
          <label class="log-viewer-search-label" for={`log-filter-${runId}`}>
            Filter
          </label>
          <input
            id={`log-filter-${runId}`}
            type="search"
            class="filter-input log-viewer-search"
            placeholder="Filter lines..."
            value={filter}
            disabled={!logs}
            onInput={(e) =>
              setFilter((e.target as HTMLInputElement).value)}
          />
          <button
            type="button"
            class="btn btn-secondary btn-sm"
            disabled={!logs}
            onClick={copyLogs}
          >
            {copyState === "done"
              ? "Copied"
              : copyState === "failed"
              ? "Copy failed"
              : "Copy all"}
          </button>
          <button
            type="button"
            class="btn btn-secondary btn-sm"
            disabled={!hasContent}
            onClick={jumpToLatest}
          >
            Jump to latest
          </button>
        </div>
      </div>

      {hasContent
        ? (
          <pre
            ref={scrollRef}
            class="log-viewer log-viewer--filled"
            onScroll={handleScroll}
            dangerouslySetInnerHTML={{ __html: renderedLogs }}
          />
        )
        : (
          <div class="log-viewer log-viewer--empty" role="status">
            <p class="log-viewer-empty-title">{empty!.title}</p>
            <p class="log-viewer-empty-detail">{empty!.detail}</p>
          </div>
        )}

      <p class="log-viewer-caption">
        Captured from scenario runner and containers
        {logPath && (
          <>
            {" "}
            ·{" "}
            <code class="log-viewer-path">{logPath}</code>
          </>
        )}
      </p>
    </div>
  );
}
