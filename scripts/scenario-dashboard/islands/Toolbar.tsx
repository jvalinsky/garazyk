import { useState } from "preact/hooks";

export default function Toolbar() {
  const [busy, setBusy] = useState(false);

  async function runAll() {
    setBusy(true);
    try {
      // Fetch all available scenarios and extract their IDs
      const scenariosResp = await fetch("/api/scenarios");
      const { scenarios } = await scenariosResp.json();
      const ids = scenarios.map((s: any) => s.id);

      if (ids.length === 0) {
        console.warn("No scenarios found to run");
        setBusy(false);
        return;
      }

      const resp = await fetch("/api/scenarios", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ids }),
      });

      if (resp.ok) {
        const data = await resp.json();
        // Could navigate to run detail page or reload
        console.log("Run started:", data.runId);
      } else {
        console.error("Failed to start run:", await resp.text());
      }
    } catch (error) {
      console.error("Error running scenarios:", error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <header class="toolbar">
      <div class="toolbar-section">
        <span class="toolbar-title">Garazyk Scenarios</span>
      </div>
      <div class="toolbar-spacer" />
      <div class="toolbar-section">
        <button class="btn btn-primary" onClick={runAll} disabled={busy}>
          {busy ? "Running scenarios..." : "Run All"}
        </button>
      </div>
    </header>
  );
}
