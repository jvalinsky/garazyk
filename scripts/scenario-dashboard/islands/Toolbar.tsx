import { useState } from "preact/hooks";

export default function Toolbar() {
  const [busy, setBusy] = useState(false);

  async function runAll() {
    setBusy(true);
    await fetch("/api/scenarios", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ids: [] }),
    });
    setBusy(false);
  }

  return (
    <header class="toolbar">
      <div class="toolbar-section">
        <span class="toolbar-title">Garazyk Scenarios</span>
      </div>
      <div class="toolbar-spacer" />
      <div class="toolbar-section">
        <input
          type="text"
          class="filter-input"
          placeholder="Filter scenarios..."
        />
      </div>
      <div class="toolbar-section">
        <button class="btn btn-primary" onClick={runAll} disabled={busy}>
          {busy ? "Running..." : "Run All ▾"}
        </button>
      </div>
    </header>
  );
}
