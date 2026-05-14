import { useState, useEffect, useRef, useMemo } from "preact/hooks";
import { AnsiUp } from "ansi_up";

interface LogViewerProps {
  runId: string;
  status: string;
}

export default function LogViewer({ runId, status }: LogViewerProps) {
  const [logs, setLogs] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const scrollRef = useRef<HTMLPreElement>(null);
  const ansiUp = useMemo(() => new AnsiUp(), []);

  const fetchLogs = async () => {
    try {
      const res = await fetch(`/api/runs/${runId}/logs`);
      if (res.ok) {
        const text = await res.text();
        setLogs(text);
      } else if (res.status === 404) {
        setLogs("Waiting for logs to start...");
      }
    } catch (e) {
      console.error("Failed to fetch logs:", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchLogs();
    
    // Poll logs if run is running
    let interval: number | undefined;
    if (status === "running") {
      interval = setInterval(fetchLogs, 2000);
    }

    return () => {
      if (interval) clearInterval(interval);
    };
  }, [runId, status]);

  // Auto-scroll to bottom when logs update
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs]);

  const renderedLogs = useMemo(() => {
    if (!logs) return "";
    return ansiUp.ansi_to_html(logs);
  }, [logs, ansiUp]);

  return (
    <div style="margin-top: var(--space-xl);">
      <h2 class="section-heading" style="display: flex; align-items: center; justify-content: space-between;">
        System Logs
        {status === "running" && <span class="badge badge-warning">Live</span>}
      </h2>
      <pre 
        ref={scrollRef}
        class="log-viewer" 
        style="height: 500px; max-height: none; background: #000; color: #eee; border: 1px solid #333; overflow-x: auto;"
        dangerouslySetInnerHTML={{ __html: renderedLogs || (loading ? "Loading logs..." : "No logs available.") }}
      />
      <div style="font-size: var(--font-size-xs); color: var(--color-text-tertiary); margin-top: var(--space-xs); text-align: right;">
        Captured from scenario runner & docker containers
      </div>
    </div>
  );
}
