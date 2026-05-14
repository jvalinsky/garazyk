export interface LocalNetworkOptions {
  withPds2?: boolean;
  useBinary?: boolean;
  keepRunning?: boolean;
  runId?: string;
  diagnosticsDir?: string;
  webClient?: string;
  clientFlow?: string;
  allowHybridNetwork?: boolean;
}

async function repoRoot(): Promise<string> {
  const proc = new Deno.Command("git", { args: ["rev-parse", "--show-toplevel"] });
  const { code, stdout } = await proc.output();
  if (code === 0) {
    const root = new TextDecoder().decode(stdout).trim();
    if (root) return root;
  }
  return Deno.cwd();
}

export async function startLocalNetwork(options: LocalNetworkOptions = {}) {
  console.log("Starting local network...");

  const root = await repoRoot();
  const scriptPath = `${root}/scripts/scenarios/setup_local_network.sh`;
  const args = [scriptPath];
  if (options.withPds2) args.push("--pds2");
  if (options.useBinary) args.push("--binary");
  if (options.keepRunning) args.push("--keep-running");
  if (options.runId) args.push("--run-id", options.runId);
  if (options.diagnosticsDir) args.push("--diagnostics-dir", options.diagnosticsDir);
  if (options.webClient) args.push("--web-client", options.webClient);
  if (options.clientFlow) args.push("--client-flow", options.clientFlow);
  if (options.allowHybridNetwork) args.push("--allow-hybrid-network");

  const command = new Deno.Command("bash", { args, stdout: "inherit", stderr: "inherit" });
  const { code } = await command.output();

  if (code !== 0) {
    throw new Error("Local network setup failed");
  }
  console.log("Local network is healthy.");
}

export async function stopLocalNetwork(
  options: LocalNetworkOptions & { collectDiagnostics?: boolean } = {},
) {
  console.log("Stopping local network...");

  const root = await repoRoot();
  const scriptPath = `${root}/scripts/scenarios/setup_local_network.sh`;
  const args = [scriptPath, "--teardown"];
  if (options.useBinary) args.push("--binary");
  if (options.collectDiagnostics) args.push("--collect-diagnostics");
  if (options.runId) args.push("--run-id", options.runId);
  if (options.diagnosticsDir) args.push("--diagnostics-dir", options.diagnosticsDir);
  if (options.webClient) args.push("--web-client", options.webClient);
  const command = new Deno.Command("bash", { args, stdout: "inherit", stderr: "inherit" });
  const { code } = await command.output();
  if (code !== 0) {
    throw new Error("Local network teardown failed");
  }
  console.log("Local network stopped.");
}
