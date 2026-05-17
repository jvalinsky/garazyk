const pkgDirs = [
  "packages/docker-client",
  "packages/atproto-client",
  "packages/atproto-topology",
  "packages/scenario-runner"
];

for (const dir of pkgDirs) {
  const p = `${dir}/deno.json`;
  const data = JSON.parse(await Deno.readTextFile(p));
  data.license = "MIT";
  
  if (dir === "packages/atproto-topology") {
    if (data.exports["./sources"]) {
      delete data.exports["./sources"];
    }
  }
  
  await Deno.writeTextFile(p, JSON.stringify(data, null, 2) + "\n");
}

let dockerTs = await Deno.readTextFile("packages/docker-client/docker.ts");
dockerTs = dockerTs.replace(
  /export async function startLocalNetwork\(options: LocalNetworkOptions = \{\}\) \{/,
  "export async function startLocalNetwork(options: LocalNetworkOptions = {}): Promise<void> {"
);
dockerTs = dockerTs.replace(
  /export async function stopLocalNetwork\(\n  options: LocalNetworkOptions & \{ collectDiagnostics\?: boolean \} = \{\},\n\) \{/,
  "export async function stopLocalNetwork(\n  options: LocalNetworkOptions & { collectDiagnostics?: boolean } = {},\n): Promise<void> {"
);
await Deno.writeTextFile("packages/docker-client/docker.ts", dockerTs);

let browserFlow = await Deno.readTextFile("packages/scenario-runner/browser_flow.ts");
browserFlow = browserFlow.replace(
  /from "npm:playwright"/,
  'from "npm:playwright@^1.40.0"'
);
await Deno.writeTextFile("packages/scenario-runner/browser_flow.ts", browserFlow);

let assertions = await Deno.readTextFile("packages/scenario-runner/assertions.ts");
assertions = assertions.replace(
  /isTrue: \(expr: boolean, msg\?: string\) =>/g,
  "isTrue: (expr: boolean, msg?: string): void =>"
);
assertions = assertions.replace(
  /isFalse: \(expr: boolean, msg\?: string\) =>/g,
  "isFalse: (expr: boolean, msg?: string): void =>"
);
assertions = assertions.replace(
  /isNotNull: \(val: any, msg\?: string\) => \{/g,
  "isNotNull: (val: any, msg?: string): void => {"
);
await Deno.writeTextFile("packages/scenario-runner/assertions.ts", assertions);

let metadata = await Deno.readTextFile("packages/scenario-runner/scenario_metadata.ts");
metadata = metadata.replace(
  /export function getParameters\(scenarioId: string\) \{/,
  "export function getParameters(scenarioId: string): Record<string, string> {"
);
await Deno.writeTextFile("packages/scenario-runner/scenario_metadata.ts", metadata);

let seed = await Deno.readTextFile("packages/atproto-client/seed.ts");
seed = seed.replace(
  /const token = String\(response\?\.token \|\| ""\);/,
  'const token = String((response as any)?.token || "");'
);
await Deno.writeTextFile("packages/atproto-client/seed.ts", seed);

console.log("Applied JSR automated fixes.");