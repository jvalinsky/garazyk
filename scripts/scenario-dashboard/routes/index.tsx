import { Handlers, PageProps } from "$fresh/server.ts";
import { getScenarios } from "../services/scenario_discovery.ts";
import { networkManager } from "../services/network_manager.ts";
import Layout from "../components/Layout.tsx";
import Toolbar from "../islands/Toolbar.tsx";
import Sidebar from "../components/Sidebar.tsx";
import StatusBar from "../components/StatusBar.tsx";
import SummaryCards from "../components/SummaryCards.tsx";
import ScenarioGrid from "../components/ScenarioGrid.tsx";
import NetworkStatus from "../islands/NetworkStatus.tsx";
import RunHistory from "../components/RunHistory.tsx";

interface PageData {
  scenarios: Awaited<ReturnType<typeof getScenarios>>;
  services: ReturnType<typeof networkManager.getStatus>;
  runs: Array<{
    id: string;
    startedAt: number;
    finishedAt?: number;
    passed: number;
    failed: number;
    skipped: number;
    total: number;
    durationS?: number;
  }>;
}

export const handler: Handlers<PageData> = {
  async GET(_req, ctx) {
    const scenarios = await getScenarios();
    const services = networkManager.getStatus();

    // Placeholder runs — will come from SQLite
    const runs: PageData["runs"] = [];

    return ctx.render({ scenarios, services, runs });
  },
};

export default function DashboardPage({ data }: PageProps<PageData>) {
  const { scenarios, services, runs } = data;

  const serviceList = Object.values(services);
  const scenarioGridData = scenarios.map((s) => ({
    id: s.id,
    name: s.name,
    status: null as null,
  }));

  return (
    <Layout title="Dashboard">
      <Toolbar />
      <Sidebar
        scenarios={scenarios}
        services={serviceList}
      />
      <main class="main-content">
        <NetworkStatus services={serviceList} />
        <SummaryCards passed={0} failed={0} skipped={0} />
        <h2 class="section-heading">Scenarios</h2>
        <ScenarioGrid scenarios={scenarioGridData} />
        <RunHistory runs={runs} />
      </main>
      <StatusBar pdsUrl="localhost:2583" />
    </Layout>
  );
}
