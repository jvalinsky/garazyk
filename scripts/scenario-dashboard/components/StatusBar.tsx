interface StatusBarProps {
  lastRun?: string;
  pdsUrl?: string;
  pdsHealthy?: boolean;
}

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
