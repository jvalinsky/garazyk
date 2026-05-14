import { Handlers, PageProps } from "$fresh/server.ts";
import { getScenarios } from "../services/scenario_discovery.ts";
import { networkManager } from "../services/network_manager.ts";
import { db } from "../db/index.ts";
import { fetchRuns, fetchLatestResultPerScenario } from "../db/queries.ts";
import Layout from "../components/Layout.tsx";
import Toolbar from "../islands/Toolbar.tsx";
import Sidebar from "../islands/Sidebar.tsx";
import StatusBar from "../components/StatusBar.tsx";
import SummaryCards from "../components/SummaryCards.tsx";
import ScenarioGrid from "../components/ScenarioGrid.tsx";
import NetworkStatus from "../islands/NetworkStatus.tsx";
import RunHistory from "../components/RunHistory.tsx";
import { formatDate } from "../utils.ts";
import { DiscoveredScenario, ServiceStatus, Run, ScenarioStatus } from "../services/types.ts";

interface ScenarioWithResults extends DiscoveredScenario {
  lastStatus?: ScenarioStatus | null;
  latestPassed?: number;
  latestFailed?: number;
  latestSkipped?: number;
}

interface PageData {
  scenarios: ScenarioWithResults[];
  services: Record<string, ServiceStatus>;
  runs: Run[];
}

export const handler: Handlers<PageData> = {
  async GET(_req, ctx) {
    const scenariosBase = await getScenarios();
    const services = networkManager.getStatus();
    const runs = fetchRuns(db, 10);

    const latestResults = fetchLatestResultPerScenario(db);
    const resultMap = new Map(latestResults.map(r => [r.scenario_id, r]));

    const scenarios = scenariosBase.map(s => {
      const res = resultMap.get(s.id);
      return {
        ...s,
        lastStatus: res?.status || null,
        latestPassed: res?.passed,
        latestFailed: res?.failed,
        latestSkipped: res?.skipped,
      };
    });

    return ctx.render({ scenarios, services, runs });
  },
};

export default function DashboardPage({ data }: PageProps<PageData>) {
  const { scenarios, services, runs } = data;

  const serviceList = Object.values(services);
  const scenarioGridData = scenarios.map((s) => ({
    id: s.id,
    name: s.name,
    status: s.lastStatus || null,
    passed: s.latestPassed,
    failed: s.latestFailed,
    skipped: s.latestSkipped,
  }));

  const latestRun = runs[0];
  const summaryLabel = latestRun ? `Latest run · ${formatDate(latestRun.startedAt)}` : undefined;

  return (
    <Layout title="Dashboard">
      <Toolbar />
      <Sidebar
        scenarios={scenarios as any}
        services={serviceList}
      />
      <main class="main-content">
        <NetworkStatus services={serviceList} />
        <SummaryCards passed={latestRun?.passed ?? 0} failed={latestRun?.failed ?? 0} skipped={latestRun?.skipped ?? 0} label={summaryLabel} />
        <h2 class="section-heading">Scenarios</h2>
        <ScenarioGrid scenarios={scenarioGridData} />
        <RunHistory runs={runs} />
      </main>
      <StatusBar pdsUrl="localhost:2583" />
    </Layout>
  );
}
