import { Handlers, PageProps } from "$fresh/server.ts";
import { getScenarios } from "../../services/scenario_discovery.ts";
import Layout from "../../components/Layout.tsx";
import Toolbar from "../../components/Toolbar.tsx";
import Sidebar from "../../components/Sidebar.tsx";
import StatusBar from "../../components/StatusBar.tsx";
import StepRow from "../../components/StepRow.tsx";

interface ScenarioPageData {
  scenario: {
    id: string;
    name: string;
    category: string;
    needsPds2: boolean;
  };
  scenarios: Awaited<ReturnType<typeof getScenarios>>;
  services: ReturnType<typeof import("../../services/network_manager.ts").networkManager.getStatus>;
  // Latest result from DB (if any)
  latestResult?: {
    status: "passed" | "failed";
    passed: number;
    failed: number;
    skipped: number;
    steps: Array<{ name: string; status: string; detail: string; duration_ms: number }>;
    artifacts?: Record<string, unknown>;
  };
}

export const handler: Handlers<ScenarioPageData> = {
  async GET(_req, ctx) {
    const { id } = ctx.params;
    const scenarios = await getScenarios();
    const { networkManager } = await import("../../services/network_manager.ts");
    const services = networkManager.getStatus();

    const scenario = scenarios.find((s) => s.id === id);
    if (!scenario) {
      return ctx.renderNotFound();
    }

    return ctx.render({
      scenario,
      scenarios,
      services,
    });
  },
};

export default function ScenarioDetailPage({ data }: PageProps<ScenarioPageData>) {
  const { scenario, scenarios, services, latestResult } = data;

  return (
    <Layout title={`Scenario ${scenario.id}: ${scenario.name}`}>
      <Toolbar />
      <Sidebar
        scenarios={scenarios}
        services={Object.values(services)}
        activeScenario={scenario.id}
      />
      <main class="main-content">
        <div style="margin-bottom: var(--space-lg);">
          <a href="/" style="color: var(--color-accent); text-decoration: none; font-size: var(--font-size-sm);">
            ← Back
          </a>
        </div>

        <h1 class="section-heading">
          Scenario {scenario.id}: {scenario.name}
        </h1>

        {latestResult ? (
          <div class="card" style="margin-bottom: var(--space-lg);">
            <div class="card-body">
              <div style="display: flex; align-items: center; gap: var(--space-md); margin-bottom: var(--space-md);">
                <span class={`badge ${latestResult.status === "passed" ? "badge-success" : "badge-destructive"}`}>
                  {latestResult.status.toUpperCase()}
                </span>
                <span style="color: var(--color-text-secondary); font-size: var(--font-size-sm);">
                  {latestResult.passed} passed · {latestResult.failed} failed · {latestResult.skipped} skipped
                </span>
              </div>
              <ul class="step-list">
                {latestResult.steps.map((step, i) => (
                  <StepRow
                    key={i}
                    name={step.name}
                    status={step.status as "passed" | "failed" | "skipped"}
                    detail={step.detail || undefined}
                    durationMs={step.duration_ms || undefined}
                  />
                ))}
              </ul>
            </div>
          </div>
        ) : (
          <div class="card" style="margin-bottom: var(--space-lg);">
            <div class="card-body" style="text-align: center; color: var(--color-text-secondary); padding: var(--space-2xl);">
              No results recorded yet for this scenario.
            </div>
          </div>
        )}

        <div style="display: flex; gap: var(--space-md);">
          <button class="btn btn-primary">
            Run This Scenario
          </button>
          {latestResult && (
            <button class="btn">
              View Full Report JSON
            </button>
          )}
        </div>

        {scenario.needsPds2 && (
          <div class="badge badge-warning" style="margin-top: var(--space-lg);">
            ⚠ Requires PDS2 — start network with PDS2 enabled
          </div>
        )}
      </main>
      <StatusBar />
    </Layout>
  );
}
