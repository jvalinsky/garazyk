/** Status bar footer — shows last run info and PDS health. @module StatusBar */

interface StatusBarProps {
  lastRun?: string;
  pdsUrl?: string;
  pdsHealthy?: boolean;
}

/** Render the status bar with last run timestamp and PDS health indicator. */
export default function StatusBar(
  { lastRun, pdsUrl, pdsHealthy }: StatusBarProps,
) {
  return (
    <footer class="status-bar" role="contentinfo">
      {lastRun && <span>Last run: {lastRun}</span>}
      {pdsUrl && (
        <span>
          PDS: {pdsUrl}{" "}
          <span class="health-dot-container">
            <span
              class={`health-dot ${pdsHealthy ? "healthy" : "unhealthy"}`}
              aria-hidden="true"
            />
            <span class="sr-only">{pdsHealthy ? "healthy" : "unhealthy"}</span>
          </span>
        </span>
      )}
    </footer>
  );
}
