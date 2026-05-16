/** Status bar footer — shows last run info and PDS health. @module StatusBar */

interface StatusBarProps {
  lastRun?: string;
  pdsUrl?: string;
  pdsHealthy?: boolean;
}

/** Render the status bar with last run timestamp and PDS health indicator. */
export default function StatusBar({ lastRun, pdsUrl, pdsHealthy }: StatusBarProps) {
  return (
    <footer class="status-bar">
      {lastRun && <span>Last run: {lastRun}</span>}
      {pdsUrl && (
        <span>
          PDS: {pdsUrl}{" "}
          <span class={`health-dot ${pdsHealthy ? "healthy" : "unhealthy"}`} />
        </span>
      )}
    </footer>
  );
}
