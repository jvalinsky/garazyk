import { Handlers, PageProps } from "$fresh/server.ts";
import { db } from "../../db/index.ts";
import { fetchRun } from "../../db/queries.ts";
import Layout from "../../components/Layout.tsx";
import Toolbar from "../../islands/Toolbar.tsx";
import RunProgress from "../../islands/RunProgress.tsx";
import LogViewer from "../../islands/LogViewer.tsx";
import StatusBar from "../../components/StatusBar.tsx";
import ScenarioCard from "../../islands/ScenarioCard.tsx";
import SummaryCards from "../../components/SummaryCards.tsx";
import { formatDate, formatDurationSec } from "../../utils.ts";
import { Run, ScenarioStatus } from "../../services/types.ts";

interface RunPageData {
  runId: string;
  run?: Run;
  scenarioResults: Array<{
    scenarioId: string;
    scenarioName: string;
    status: ScenarioStatus;
    passed: number;
    failed: number;
    skipped: number;
  }>;
}

export const handler: Handlers<RunPageData> = {
  GET(_req, ctx) {
    const { runId } = ctx.params;

    try {
      const run = fetchRun(db, runId);

      let scenarioResults: RunPageData["scenarioResults"] = [];
      
      if (run) {
        scenarioResults = db.prepare(`
          SELECT scenario_id as scenarioId, scenario_name as scenarioName, status, passed, failed, skipped
          FROM scenario_results
          WHERE run_id = ?
          ORDER BY scenario_id ASC
        `).all(runId) as RunPageData["scenarioResults"];
      }

      return ctx.render({ runId, run, scenarioResults });
    } catch (e) {
      console.error("Error fetching run details:", e);
      return ctx.render({ runId, scenarioResults: [] });
    }
  },
};

export default function RunDetailPage({ data }: PageProps<RunPageData>) {
  const { runId, run, scenarioResults = [] } = data;

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

        {run && (
          <>
            <RunProgress runId={runId} startedAt={run.startedAt} status={run.status} />
            <div style="display: flex; gap: var(--space-xl); margin-bottom: var(--space-lg); font-size: var(--font-size-sm); color: var(--color-text-secondary); flex-wrap: wrap;">
              <span>Started: {formatDate(run.startedAt)}</span>
              {run.finishedAt && <span>Duration: {formatDurationSec(run.durationS ?? 0)}</span>}
              <span class={`badge ${run.status === "completed" ? "badge-success" : run.status === "error" ? "badge-destructive" : "badge-warning"}`}>{run.status}</span>
              {run.pds2 && <span class="badge badge-info">PDS2</span>}
              {run.binaryMode && <span class="badge badge-secondary">binary</span>}
            </div>
          </>
        )}

        {run ? (
          <>
            <SummaryCards passed={run.passed} failed={run.failed} skipped={run.skipped} />

            {scenarioResults.length > 0 && (
              <div class="scenario-grid">
                {scenarioResults.map((sr) => (
                  <ScenarioCard
                    key={sr.scenarioId}
                    id={sr.scenarioId}
                    name={sr.scenarioName}
                    status={sr.status as any}
                    passed={sr.passed}
                    failed={sr.failed}
                    skipped={sr.skipped}
                    runId={runId}
                  />
                ))}
              </div>
            )}

            <LogViewer runId={runId} status={run.status} />
          </>
        ) : (
          <div class="card">
            <div class="card-body" style="text-align: center; color: var(--color-text-secondary); padding: var(--space-2xl);">
              Run {runId} not found in database.
            </div>
          </div>
        )}
      </main>
      <StatusBar />
    </Layout>
  );
}
