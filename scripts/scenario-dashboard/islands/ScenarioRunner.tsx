import { useState } from "preact/hooks";

interface ScenarioRunnerProps {
  scenarioId: string;
  needsPds2: boolean;
}

export default function ScenarioRunner({ scenarioId, needsPds2 }: ScenarioRunnerProps) {
  const [running, setRunning] = useState(false);

  const handleRun = async () => {
    setRunning(true);
    try {
      const res = await fetch("/api/scenarios", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ids: [scenarioId], pds2: needsPds2 }),
      });
      if (res.ok) {
        const data = await res.json();
        // Redirect to the new run page
        window.location.href = `/run/${data.runId}`;
      } else {
        alert("Failed to start run");
      }
    } catch (e) {
      alert("Error starting run: " + e);
    } finally {
      setRunning(false);
    }
  };

  return (
    <button class="btn btn-primary" onClick={handleRun} disabled={running}>
      {running ? "Starting Run..." : "Run This Scenario"}
    </button>
  );
}
