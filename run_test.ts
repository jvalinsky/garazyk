import { renderComposeYaml } from "./packages/schemat/topology_compiler.ts";
const preset = {
  name: "test-preset",
  roles: {
    pds: {
      name: "reference-pds",
      image: "ghcr.io/bluesky-social/atproto/pds:latest",
      healthCheck: { path: "/xrpc/com.atproto.server.describeServer" },
      capabilities: ["describeServer"],
    }
  }
};
console.log(renderComposeYaml(preset as any, {
  preset: "test",
  runDir: "/tmp",
  repoRoot: "/repo",
  composeProject: "test"
}));
