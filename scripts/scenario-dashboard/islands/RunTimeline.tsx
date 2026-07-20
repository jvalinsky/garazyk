/** Run event timeline scrubber. @module RunTimeline */
import { useEffect, useMemo, useState } from "preact/hooks";
import type { TimelineEventRow } from "../lib/timeline.ts";

interface TimelineMarker {
  id: number;
  t: number;
  label: string;
  eventType: string;
}

interface RunEventApiRow extends TimelineEventRow {
  id: number;
  timestamp: number;
  detail: {
    type: string;
    scenarioId?: string;
    scenarioName?: string;
    status?: string;
  };
}

interface RunTimelineProps {
  runId: string;
  startedAt: number;
  /** Pre-fetched events (avoids duplicate API calls). */
  events?: RunEventApiRow[];
  /** Called with offset ms from run start when user scrubs. */
  onSeek?: (offsetMs: number) => void;
}

function buildMarkers(
  rows: RunEventApiRow[],
  startedAt: number,
): { markers: TimelineMarker[]; durationMs: number } {
  const ms = rows.map((r) => r.timestamp - startedAt);
  const durationMs = ms.length > 0 ? Math.max(...ms, 0) : 0;
  const markers: TimelineMarker[] = [];

  for (const row of rows) {
    const t = Math.max(0, row.timestamp - startedAt);
    if (row.eventType === "scenario_started") {
      const d = row.detail;
      markers.push({
        id: row.id,
        t,
        eventType: row.eventType,
        label: `${d.scenarioId ?? "?"} started`,
      });
    } else if (row.eventType === "scenario_finished") {
      const d = row.detail;
      markers.push({
        id: row.id,
        t,
        eventType: row.eventType,
        label: `${d.scenarioId ?? "?"} ${d.status ?? "done"}`,
      });
    } else if (row.eventType === "run_failed") {
      markers.push({
        id: row.id,
        t,
        eventType: row.eventType,
        label: "Run failed",
      });
    }
  }
  return { markers, durationMs };
}

/** Fetch and render scenario/step markers with a scrubber. */
export default function RunTimeline(
  { runId, startedAt, events: eventsProp, onSeek }: RunTimelineProps,
) {
  const [markers, setMarkers] = useState<TimelineMarker[]>([]);
  const [durationMs, setDurationMs] = useState(0);
  const [position, setPosition] = useState(0);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    if (eventsProp) {
      const { markers: m, durationMs: d } = buildMarkers(eventsProp, startedAt);
      setMarkers(m);
      setDurationMs(d);
      return;
    }

    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(
          `/api/runs/${encodeURIComponent(runId)}/events`,
        );
        if (!res.ok) {
          if (res.status === 404) {
            setMarkers([]);
            return;
          }
          throw new Error(`events ${res.status}`);
        }
        const rows = await res.json() as RunEventApiRow[];
        if (cancelled) return;
        const { markers: m, durationMs: d } = buildMarkers(rows, startedAt);
        setMarkers(m);
        setDurationMs(d);
      } catch (e) {
        if (!cancelled) setLoadError((e as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [runId, startedAt, eventsProp]);

  const label = useMemo(() => {
    const sec = (position / 1000).toFixed(1);
    const near = markers.find((m) => Math.abs(m.t - position) < 500);
    return near ? `${sec}s — ${near.label}` : `${sec}s`;
  }, [position, markers]);

  if (loadError) {
    return (
      <p class="text-secondary text-sm">
        Timeline unavailable: {loadError}
      </p>
    );
  }

  if (markers.length === 0 && durationMs === 0) {
    return null;
  }

  return (
    <div
      class="card mb-lg"
      role="region"
      aria-label="Run timeline"
    >
      <div class="card-header section-title-inline">
        Timeline
      </div>
      <div class="card-body p-md">
        <label
          for={`timeline-${runId}`}
          class="d-block text-sm text-secondary mb-sm"
        >
          {label}
        </label>
        <input
          id={`timeline-${runId}`}
          type="range"
          min={0}
          max={Math.max(durationMs, 1)}
          value={position}
          onInput={(e) => {
            const v = Number((e.target as HTMLInputElement).value);
            setPosition(v);
            onSeek?.(v);
          }}
          class="w-full"
          aria-valuetext={label}
        />
        <div class="d-flex flex-wrap gap-xs mt-sm">
          {markers.map((m) => (
            <button
              key={m.id}
              type="button"
              class="badge badge-secondary cursor-pointer border-none"
              onClick={() => {
                setPosition(m.t);
                onSeek?.(m.t);
              }}
            >
              {m.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
