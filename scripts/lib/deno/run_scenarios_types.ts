import type { BrowserFlow } from "./topology.ts";

export interface RunnerArgs {
  scenarioIds: string[];
  list: boolean;
  setupOnly: boolean;
  setup: boolean;
  teardown: boolean;
  teardownOnly: boolean;
  noSetup: boolean;
  binary: boolean;
  pds2: boolean;
  verbose: boolean;
  noJson: boolean;
  keepRunning: boolean;
  collectDiagnostics: boolean;
  timeout: number;
  clientFlow: BrowserFlow;
  webClient?: string;
  allowHybridNetwork: boolean;
  runId?: string;
  diagnosticsDir?: string;
  reportsDir?: string;
  topology?: string;
  runner: "host" | "docker";
  otel: boolean;
}
