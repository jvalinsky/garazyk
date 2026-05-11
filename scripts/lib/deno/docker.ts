export async function startLocalNetwork(withPds2 = false) {
  console.log("Starting local network via Docker...");
  
  // Try to find the repo root
  const proc = new Deno.Command("git", { args: ["rev-parse", "--show-toplevel"] });
  const { stdout } = await proc.output();
  const repoRoot = new TextDecoder().decode(stdout).trim() || Deno.cwd();

  const scriptPath = `${repoRoot}/scripts/scenarios/setup_local_network.sh`;
  const args = [scriptPath];
  if (withPds2) args.push("--pds2");

  const command = new Deno.Command("bash", { args, stdout: "inherit", stderr: "inherit" });
  const { code } = await command.output();
  
  if (code !== 0) {
    throw new Error("Docker setup failed");
  }
  console.log("Local network is healthy.");
}

export async function stopLocalNetwork() {
  console.log("Stopping local network...");
  
  const proc = new Deno.Command("git", { args: ["rev-parse", "--show-toplevel"] });
  const { stdout } = await proc.output();
  const repoRoot = new TextDecoder().decode(stdout).trim() || Deno.cwd();

  const scriptPath = `${repoRoot}/scripts/scenarios/setup_local_network.sh`;
  const command = new Deno.Command("bash", { args: [scriptPath, "--teardown"], stdout: "inherit", stderr: "inherit" });
  await command.output();
  console.log("Local network stopped.");
}
