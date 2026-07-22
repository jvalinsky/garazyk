/** Asciinema player island for TUI session recordings. @module SessionPlayer */
import { useEffect, useRef, useState } from "preact/hooks";

const ASCIINEMA_PLAYER_CSS =
  "https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.css";
const ASCIINEMA_PLAYER_SCRIPT =
  "https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.min.js";

interface AsciinemaPlayerInstance {
  dispose?: () => void;
}

interface AsciinemaPlayerAPI {
  create(
    src: string | { data: () => Promise<string> },
    el: HTMLElement,
    opts?: Record<string, unknown>,
  ): AsciinemaPlayerInstance;
}

function installedAsciinemaPlayer(): AsciinemaPlayerAPI | undefined {
  return (globalThis as typeof globalThis & {
    AsciinemaPlayer?: AsciinemaPlayerAPI;
  }).AsciinemaPlayer;
}

function loadAsciinemaPlayer(): Promise<AsciinemaPlayerAPI> {
  const existing = installedAsciinemaPlayer();
  if (existing) return Promise.resolve(existing);

  return new Promise((resolve, reject) => {
    let script = document.querySelector<HTMLScriptElement>(
      "script[data-asciinema-player]",
    );
    if (!script) {
      script = document.createElement("script");
      script.async = true;
      script.src = ASCIINEMA_PLAYER_SCRIPT;
      script.setAttribute("data-asciinema-player", "1");
      document.head.appendChild(script);
    }

    script.addEventListener("load", () => {
      const player = installedAsciinemaPlayer();
      if (player) {
        resolve(player);
      } else {
        reject(new Error("asciinema-player bundle loaded without its API"));
      }
    }, { once: true });
    script.addEventListener("error", () => {
      reject(new Error("Failed to load the asciinema-player browser bundle"));
    }, { once: true });
  });
}

interface SessionPlayerProps {
  /** URL to fetch .cast content (e.g. /api/runs/id/tui-cast). */
  castUrl: string;
}

/** Embeds asciinema-player for terminal session playback. */
export default function SessionPlayer({ castUrl }: SessionPlayerProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<AsciinemaPlayerInstance | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    let cancelled = false;
    setError(null);
    setLoading(true);

    (async () => {
      try {
        if (!document.querySelector("link[data-asciinema-player]")) {
          const link = document.createElement("link");
          link.rel = "stylesheet";
          link.setAttribute("data-asciinema-player", "1");
          link.href = ASCIINEMA_PLAYER_CSS;
          document.head.appendChild(link);
        }

        const AsciinemaPlayer = await loadAsciinemaPlayer();

        if (cancelled) return;

        playerRef.current?.dispose?.();
        container.replaceChildren();

        playerRef.current = AsciinemaPlayer.create(
          {
            data: async () => {
              const res = await fetch(castUrl);
              if (!res.ok) {
                throw new Error(`Failed to load cast (${res.status})`);
              }
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
    <div class="card mb-lg">
      <div class="card-header section-title-inline">
        TUI session replay
      </div>
      <div class="card-body p-md">
        {loading && !error && (
          <p class="text-secondary m-0">
            Loading terminal recording…
          </p>
        )}
        {error && <p class="text-destructive m-0">{error}</p>}
        <div ref={containerRef} />
      </div>
    </div>
  );
}
