/** Coordinates timeline scrubbing with log and TUI replay. @module RunReplayPanel */
import { useCallback, useEffect, useState } from "preact/hooks";
import RunTimeline from "./RunTimeline.tsx";
import SessionPlayer from "./SessionPlayer.tsx";
import LogViewer from "./LogViewer.tsx";
import ExportReplayButton from "./ExportReplayButton.tsx";
import {
  offsetMsToLogLineIndex,
  type TimelineEventRow,
} from "../lib/timeline.ts";

interface RunEventApiRow extends TimelineEventRow {
  id: number;
  timestamp: number;
}

interface RunReplayPanelProps {
  runId: string;
  startedAt: number;
  status: string;
  logPath?: string | null;
  hasTuiCast: boolean;
}

/** Run replay section: timeline, optional TUI player, logs, export. */
export default function RunReplayPanel({
  runId,
  startedAt,
  status,
  logPath,
  hasTuiCast,
}: RunReplayPanelProps) {
  const [events, setEvents] = useState<RunEventApiRow[]>([]);
  const [scrollToLine, setScrollToLine] = useState<number | undefined>(
    undefined,
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/runs/${encodeURIComponent(runId)}/events`);
        if (!res.ok) return;
        const rows = await res.json() as RunEventApiRow[];
        if (!cancelled) setEvents(rows);
      } catch {
        // timeline still works without events
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [runId]);

  const onSeek = useCallback((offsetMs: number) => {
    const lineIdx = offsetMsToLogLineIndex(events, startedAt, offsetMs);
    setScrollToLine(lineIdx);
  }, [events, startedAt]);

  return (
    <>
      <div
        style="display: flex; align-items: center; justify-content: space-between; margin-bottom: var(--space-md); flex-wrap: wrap; gap: var(--space-sm);"
      >
        <h2 class="section-heading" style="margin: 0;">Replay</h2>
        <ExportReplayButton runId={runId} />
      </div>
      <RunTimeline
        runId={runId}
        startedAt={startedAt}
        events={events}
        onSeek={onSeek}
      />
      {hasTuiCast && (
        <SessionPlayer
          castUrl={`/api/runs/${encodeURIComponent(runId)}/tui-cast`}
        />
      )}
      <LogViewer
        runId={runId}
        status={status}
        logPath={logPath}
        scrollToLine={scrollToLine}
      />
    </>
  );
}
