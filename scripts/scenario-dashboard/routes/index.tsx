import { Handlers, PageProps } from "$fresh/server.ts";
import { getScenarios } from "../services/scenario_discovery.ts";
import { networkManager } from "../services/network_manager.ts";
import { db } from "../db/index.ts";
import Layout from "../components/Layout.tsx";
import Toolbar from "../islands/Toolbar.tsx";
import Sidebar from "../components/Sidebar.tsx";
import StatusBar from "../components/StatusBar.tsx";
import SummaryCards from "../components/SummaryCards.tsx";
import ScenarioGrid from "../components/ScenarioGrid.tsx";
import NetworkStatus from "../islands/NetworkStatus.tsx";
import RunHistory from "../components/RunHistory.tsx";

interface PageData {
  scenarios: Array<Awaited<ReturnType<typeof getScenarios>>[0] & {
    latestStatus?: "passed" | "failed" | "skipped" | "running" | null;
    latestPassed?: number;
    latestFailed?: number;
    latestSkipped?: number;
  }>;
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
    const scenariosBase = await getScenarios();
    const services = networkManager.getStatus();

    const runs = db.prepare(`
      SELECT id, started_at as startedAt, finished_at as finishedAt, passed, failed, skipped, total_scenarios as total, duration_s as durationS 
      FROM runs 
      ORDER BY started_at DESC 
      LIMIT 10
    `).all() as PageData["runs"];

    const latestResults = db.prepare(`
      SELECT scenario_id, status, passed, failed, skipped
      FROM scenario_results
      GROUP BY scenario_id
      HAVING started_at = MAX(started_at)
    `).all() as Array<{ scenario_id: string, status: string, passed: number, failed: number, skipped: number }>;

    const resultMap = new Map(latestResults.map(r => [r.scenario_id, r]));

    const scenarios = scenariosBase.map(s => {
      const res = resultMap.get(s.id);
      return {
        ...s,
        latestStatus: res?.status as any,
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
    status: s.latestStatus || null,
    passed: s.latestPassed,
    failed: s.latestFailed,
    skipped: s.latestSkipped,
  }));

  const totalPassed = scenarios.reduce((sum, s) => sum + (s.latestPassed || 0), 0);
  const totalFailed = scenarios.reduce((sum, s) => sum + (s.latestFailed || 0), 0);
  const totalSkipped = scenarios.reduce((sum, s) => sum + (s.latestSkipped || 0), 0);

  return (
    <Layout title="Dashboard">
      <Toolbar />
      <Sidebar
        scenarios={scenarios}
        services={serviceList}
      />
      <main class="main-content">
        <NetworkStatus services={serviceList} />
        <SummaryCards passed={totalPassed} failed={totalFailed} skipped={totalSkipped} />
        <h2 class="section-heading">Scenarios</h2>
        <ScenarioGrid scenarios={scenarioGridData} />
        <RunHistory runs={runs} />
      </main>
      <StatusBar pdsUrl="localhost:2583" />
    </Layout>
  );
}
