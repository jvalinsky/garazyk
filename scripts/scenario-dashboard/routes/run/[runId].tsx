import { Handlers, PageProps } from "$fresh/server.ts";
import { db } from "../../db/index.ts";
import { fetchRun, fetchScenarioResults } from "../../db/queries.ts";
import Layout from "../../components/Layout.tsx";
import Toolbar from "../../islands/Toolbar.tsx";
import MobileNav from "../../islands/MobileNav.tsx";
import RunProgress from "../../islands/RunProgress.tsx";
import RunReplayPanel from "../../islands/RunReplayPanel.tsx";
import { resolveRunArtifact, RUN_ARTIFACTS } from "../../lib/artifacts.ts";
import StatusBar from "../../components/StatusBar.tsx";
import ScenarioCard from "../../islands/ScenarioCard.tsx";
import SummaryCards from "../../components/SummaryCards.tsx";
import FailureTriage from "../../components/FailureTriage.tsx";
import { formatDate, formatDurationSec } from "../../utils.ts";
import { Run, ScenarioResultView } from "../../services/types.ts";

interface RunPageData {
  runId: string;
  run?: Run;
  scenarioResults: ScenarioResultView[];
  hasTuiCast: boolean;
}

/** Page handler for run detail data. */
export const handler: Handlers<RunPageData> = {
  async GET(_req, ctx) {
    const { runId } = ctx.params;

    try {
      const run = fetchRun(db, runId);

      const scenarioResults = run ? fetchScenarioResults(db, runId) : [];
      const hasTuiCast = !!(run?.runDir &&
        await resolveRunArtifact(run.runDir, RUN_ARTIFACTS.tuiCast));

      return ctx.render({ runId, run, scenarioResults, hasTuiCast });
    } catch (e) {
      console.error("Error fetching run details:", e);
      return ctx.render({ runId, scenarioResults: [], hasTuiCast: false });
    }
  },
};

/** Page component for run details. */
export default function RunDetailPage({ data }: PageProps<RunPageData>) {
  const { runId, run, scenarioResults = [], hasTuiCast } = data;
  const orderedScenarioResults = [...scenarioResults].sort((a, b) => {
    const aRank = a.status === "failed" || a.failed > 0 ? 0 : 1;
    const bRank = b.status === "failed" || b.failed > 0 ? 0 : 1;
    if (aRank !== bRank) return aRank - bRank;
    return a.scenarioId.localeCompare(b.scenarioId, undefined, {
      numeric: true,
    });
  });

  return (
    <Layout title={`Run ${runId}`} hasOwnH1>
      <Toolbar />
      <main class="main-content">
        <div class="mb-lg">
          <a href="/" class="link-subtle">
            ← Back to Dashboard
          </a>
        </div>

        <h1 class="section-heading">Run: {runId}</h1>

        {run && (
          <>
            <RunProgress
              runId={runId}
              startedAt={run.startedAt}
              status={run.status}
              totalScenarios={run.totalScenarios}
              completedScenarios={run.passed + run.failed + run.skipped}
              agentMode={run.agentMode}
            />
            <div class="d-flex gap-xl mb-lg text-sm text-secondary flex-wrap">
              <span>Started: {formatDate(run.startedAt)}</span>
              {run.finishedAt && (
                <span>Duration: {formatDurationSec(run.durationS ?? 0)}</span>
              )}
              <span
                class={`badge ${
                  run.status === "completed"
                    ? "badge-success"
                    : run.status === "error"
                    ? "badge-destructive"
                    : "badge-warning"
                }`}
              >
                {run.status}
              </span>
              {run.pds2 && <span class="badge badge-info">PDS2</span>}
              {run.binaryMode && (
                <span class="badge badge-secondary">binary</span>
              )}
              {run.agentMode && (
                <span class="badge badge-secondary">Agent</span>
              )}
            </div>
          </>
        )}

        {run
          ? (
            <>
              <FailureTriage run={run} results={scenarioResults} />

              <SummaryCards
                passed={run.passed}
                failed={run.failed}
                skipped={run.skipped}
              />

              {orderedScenarioResults.length > 0 && (
                <div class="scenario-grid">
                  {orderedScenarioResults.map((sr) => (
                    <ScenarioCard
                      key={sr.scenarioId}
                      id={sr.scenarioId}
                      name={sr.scenarioName}
                      status={sr.status}
                      passed={sr.passed}
                      failed={sr.failed}
                      skipped={sr.skipped}
                      runId={runId}
                    />
                  ))}
                </div>
              )}

              <RunReplayPanel
                runId={runId}
                startedAt={run.startedAt}
                status={run.status}
                logPath={run.logPath}
                hasTuiCast={hasTuiCast}
              />
            </>
          )
          : (
            <div class="card">
              <div class="card-body empty-state">
                Run {runId} not found in database.
              </div>
            </div>
          )}
      </main>
      <StatusBar />
      <MobileNav />
    </Layout>
  );
}
