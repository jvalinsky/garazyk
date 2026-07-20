import { Handlers, PageProps } from "$fresh/server.ts";
import { getScenarios } from "../../services/scenario_discovery.ts";
import { db } from "../../db/index.ts";
import Layout from "../../components/Layout.tsx";
import Toolbar from "../../islands/Toolbar.tsx";
import Sidebar from "../../islands/Sidebar.tsx";
import MobileNav from "../../islands/MobileNav.tsx";
import StatusBar from "../../components/StatusBar.tsx";
import StepRow from "../../components/StepRow.tsx";
import ScenarioRunner from "../../islands/ScenarioRunner.tsx";
import type {
  DiscoveredScenario,
  ScenarioStatus,
  Step,
} from "../../services/types.ts";

interface ScenarioPageData {
  scenario: DiscoveredScenario;
  latestResult?: {
    status: ScenarioStatus;
    passed: number;
    failed: number;
    skipped: number;
    steps: Step[];
    artifacts?: Record<string, unknown>;
  };
}

/** Page handler for scenario detail data. */
export const handler: Handlers<ScenarioPageData> = {
  async GET(req, ctx) {
    try {
      const { id } = ctx.params;
      const url = new URL(req.url);
      const runId = url.searchParams.get("runId");

      const scenarios = await getScenarios();

      let scenario = scenarios.find((s) => s.id === id);

      let latestResult: ScenarioPageData["latestResult"] = undefined;
      let dbScenarioName: string | undefined = undefined;

      try {
        let query = `
          SELECT status, passed, failed, skipped, steps_json as stepsJson, artifacts_json as artifactsJson, scenario_name as scenarioName
          FROM scenario_results
          WHERE scenario_id = ?
        `;
        const params: string[] = [id];

        if (runId) {
          query += " AND run_id = ?";
          params.push(runId);
        } else {
          query += " ORDER BY started_at DESC LIMIT 1";
        }

        const resultRow = db.prepare(query).get(...params) as {
          status: ScenarioStatus;
          passed: number;
          failed: number;
          skipped: number;
          stepsJson: string;
          artifactsJson?: string;
          scenarioName: string;
        } | undefined;

        if (resultRow) {
          dbScenarioName = resultRow.scenarioName;
          latestResult = {
            status: resultRow.status,
            passed: resultRow.passed,
            failed: resultRow.failed,
            skipped: resultRow.skipped,
            steps: (JSON.parse(resultRow.stepsJson || "[]") as any[]).map((
              s,
            ) => ({
              name: s.name,
              status: s.status,
              detail: s.detail,
              durationMs: s.duration_ms,
            })),
            artifacts: resultRow.artifactsJson
              ? JSON.parse(resultRow.artifactsJson)
              : undefined,
          };
        }
      } catch (e) {
        console.error("Error fetching scenario result from DB:", e);
      }

      if (!scenario) {
        if (dbScenarioName) {
          scenario = {
            id,
            name: dbScenarioName,
            description: "",
            path: "",
            category: "unknown",
            needsPds2: false,
          };
        } else {
          return ctx.renderNotFound();
        }
      }

      return ctx.render({
        scenario: scenario!,
        latestResult,
      });
    } catch (e) {
      console.error("Fatal error in scenario detail handler:", e);
      return ctx.renderNotFound();
    }
  },
};

/** Scenario detail page component. */
export default function ScenarioDetailPage(
  { data }: PageProps<ScenarioPageData>,
) {
  const { scenario, latestResult } = data;

  return (
    <Layout title={`Scenario ${scenario.id}: ${scenario.name}`} hasOwnH1>
      <Toolbar />
      <Sidebar activeScenario={scenario.id} />
      <main class="main-content">
        <div style="margin-bottom: var(--space-lg);">
          <a
            href="/"
            style="color: var(--color-accent); text-decoration: none; font-size: var(--font-size-sm);"
          >
            ← Back
          </a>
        </div>

        <h1 class="section-heading">
          Scenario {scenario.id}: {scenario.name}
        </h1>

        {latestResult
          ? (
            <div class="card" style="margin-bottom: var(--space-lg);">
              <div class="card-body">
                <div style="display: flex; align-items: center; gap: var(--space-md); margin-bottom: var(--space-md);">
                  <span
                    class={`badge ${
                      latestResult.status === "passed"
                        ? "badge-success"
                        : latestResult.status === "failed"
                        ? "badge-destructive"
                        : latestResult.status === "running"
                        ? "badge-info"
                        : "badge-secondary"
                    }`}
                  >
                    {latestResult.status.toUpperCase()}
                  </span>
                  <span style="color: var(--color-text-secondary); font-size: var(--font-size-sm);">
                    {latestResult.passed} passed · {latestResult.failed}{" "}
                    failed · {latestResult.skipped} skipped
                  </span>
                </div>
                <ul class="step-list">
                  {latestResult.steps.map((step, i) => (
                    <StepRow
                      key={i}
                      name={step.name}
                      status={step.status as "passed" | "failed" | "skipped"}
                      detail={step.detail || undefined}
                      durationMs={step.durationMs || undefined}
                    />
                  ))}
                </ul>
              </div>
            </div>
          )
          : (
            <div class="card" style="margin-bottom: var(--space-lg);">
              <div
                class="card-body"
                style="text-align: center; color: var(--color-text-secondary); padding: var(--space-2xl);"
              >
                No results recorded yet for this scenario.
              </div>
            </div>
          )}

        <div style="display: flex; gap: var(--space-md);">
          <ScenarioRunner
            scenarioId={scenario.id}
            needsPds2={scenario.needsPds2}
          />
        </div>

        {scenario.needsPds2 && (
          <div class="badge badge-warning" style="margin-top: var(--space-lg);">
            ⚠ Requires PDS2 — start network with PDS2 enabled
          </div>
        )}
      </main>
      <StatusBar />
      <MobileNav activeScenario={scenario.id} />
    </Layout>
  );
}
