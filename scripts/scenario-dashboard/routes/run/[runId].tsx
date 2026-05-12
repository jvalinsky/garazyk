import { Handlers, PageProps } from "$fresh/server.ts";
import { db } from "../../db/index.ts";
import Layout from "../../components/Layout.tsx";
import Toolbar from "../../components/Toolbar.tsx";
import StatusBar from "../../components/StatusBar.tsx";
import ScenarioCard from "../../components/ScenarioCard.tsx";

interface RunPageData {
  runId: string;
  run?: {
    id: string;
    startedAt: number;
    finishedAt?: number;
    passed: number;
    failed: number;
    skipped: number;
    total: number;
    durationS?: number;
    status: string;
  };
  scenarioResults?: Array<{
    scenarioId: string;
    scenarioName: string;
    status: string;
    passed: number;
    failed: number;
    skipped: number;
  }>;
}

export const handler: Handlers<RunPageData> = {
  GET(_req, ctx) {
    const { runId } = ctx.params;

    const run = db.prepare(`
      SELECT id, started_at as startedAt, finished_at as finishedAt, passed, failed, skipped, total_scenarios as total, duration_s as durationS, status
      FROM runs 
      WHERE id = ?
    `).get(runId) as RunPageData["run"] | undefined;

    let scenarioResults: RunPageData["scenarioResults"] = undefined;
    
    if (run) {
      scenarioResults = db.prepare(`
        SELECT scenario_id as scenarioId, scenario_name as scenarioName, status, passed, failed, skipped
        FROM scenario_results
        WHERE run_id = ?
        ORDER BY scenario_id ASC
      `).all(runId) as RunPageData["scenarioResults"];
    }

    return ctx.render({ runId, run, scenarioResults });
  },
};

export default function RunDetailPage({ data }: PageProps<RunPageData>) {
  const { runId, run, scenarioResults } = data;

  return (
    <Layout title={`Run ${runId}`}>
      <Toolbar />
      <main class="main-content">
        <div style="margin-bottom: var(--space-lg);">
          <a href="/" style="color: var(--color-accent); text-decoration: none; font-size: var(--font-size-sm);">
            ← Back to Dashboard
          </a>
        </div>

        <h1 class="section-heading">Run: {runId}</h1>

        {run ? (
          <>
            <div class="summary-row">
              <div class="summary-card passed">
                <div class="label">Passed</div>
                <div class="value">{run.passed}</div>
              </div>
              <div class="summary-card failed">
                <div class="label">Failed</div>
                <div class="value">{run.failed}</div>
              </div>
              <div class="summary-card skipped">
                <div class="label">Skipped</div>
                <div class="value">{run.skipped}</div>
              </div>
            </div>

            {scenarioResults && scenarioResults.length > 0 && (
              <div class="scenario-grid">
                {scenarioResults.map((sr) => (
                  <ScenarioCard
                    key={sr.scenarioId}
                    id={sr.scenarioId}
                    name={sr.scenarioName}
                    status={sr.status as "passed" | "failed"}
                    passed={sr.passed}
                    failed={sr.failed}
                    skipped={sr.skipped}
                  />
                ))}
              </div>
            )}
          </>
        ) : (
          <div class="card">
            <div class="card-body" style="text-align: center; color: var(--color-text-secondary); padding: var(--space-2xl);">
              Run not found.
            </div>
          </div>
        )}
      </main>
      <StatusBar />
    </Layout>
  );
}
