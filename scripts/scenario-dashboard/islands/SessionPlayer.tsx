/** Asciinema player island for TUI session recordings. @module SessionPlayer */
import { useEffect, useRef, useState } from "preact/hooks";

interface SessionPlayerProps {
  /** URL to fetch .cast content (e.g. /api/runs/id/tui-cast). */
  castUrl: string;
}

/** Embeds asciinema-player for terminal session playback. */
export default function SessionPlayer({ castUrl }: SessionPlayerProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<{ dispose?: () => void } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    let cancelled = false;

    (async () => {
      try {
        if (!document.querySelector('link[data-asciinema-player]')) {
          const link = document.createElement("link");
          link.rel = "stylesheet";
          link.setAttribute("data-asciinema-player", "1");
          link.href =
            "https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.css";
          document.head.appendChild(link);
        }

        const mod = await import("asciinema-player");
        const AsciinemaPlayer = mod as {
          create: (
            src: string | { data: () => Promise<string> },
            el: HTMLElement,
            opts?: Record<string, unknown>,
          ) => { dispose?: () => void };
        };

        if (cancelled) return;

        playerRef.current?.dispose?.();
        container.innerHTML = "";

        playerRef.current = AsciinemaPlayer.create(
          {
            data: async () => {
              const res = await fetch(castUrl);
              if (!res.ok) throw new Error(`Failed to load cast (${res.status})`);
              return await res.text();
            },
          },
          container,
          {
            cols: 120,
            rows: 30,
            autoPlay: false,
            preload: true,
            terminalFontSize: "small",
          },
        );
        setLoading(false);
      } catch (e) {
        if (!cancelled) {
          setError((e as Error).message);
          setLoading(false);
        }
      }
    })();

    return () => {
      cancelled = true;
      playerRef.current?.dispose?.();
      playerRef.current = null;
    };
  }, [castUrl]);

  return (
    <div class="card" style="margin-bottom: var(--space-lg);">
      <div
        class="card-header"
        style="font-size: var(--font-size-sm); font-weight: 600;"
      >
        TUI session replay
      </div>
      <div class="card-body" style="padding: var(--space-md);">
        {loading && !error && (
          <p style="color: var(--color-text-secondary); margin: 0;">
            Loading terminal recording…
          </p>
        )}
        {error && (
          <p style="color: var(--color-destructive); margin: 0;">{error}</p>
        )}
        <div ref={containerRef} />
      </div>
    </div>
  );
}
