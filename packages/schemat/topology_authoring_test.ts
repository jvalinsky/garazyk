import { assertEquals } from "@std/assert";
import {
  Cap,
  defineTopology,
  health,
  port,
  requires,
  Role,
  role,
  source,
  TopologyRegistry,
  volume,
} from "./mod.ts";
import { compileTopology, renderComposeYaml } from "./topology_compiler.ts";
import {
  normalizeTopologyPreset,
  parseRawTopologyPresetV1,
} from "./topology_schema.ts";

const typeCheckedPreset = defineTopology({
  name: "type-checked-authoring",
  description: "Compile-time capability checks",
  roles: {
    [Role.pds]: role.pds({
      name: "typed-pds",
      source: source.image("example/pds:latest"),
      health: health.http("/xrpc/com.atproto.server.describeServer"),
      capabilities: [
        Cap.pds.describeServer,
        // @ts-expect-error relay capabilities are rejected for pds roles.
        Cap.relay.listRepos,
      ],
    }),
  },
});
void typeCheckedPreset;

// @ts-expect-error relay capabilities are rejected for pds requirements.
const badRequirement = requires(Role.pds, Cap.relay.listRepos);
void badRequirement;

Deno.test("defineTopology: typed service normalizes like equivalent raw preset", () => {
  const typed = defineTopology({
    name: "typed-normalization",
    description: "Typed topology normalization",
    roles: {
      [Role.pds]: role.pds({
        name: "typed-pds",
        source: source.image("example/pds:latest"),
        ports: [port(2583)],
        volumes: [volume.named("typed_pds_data", "/data")],
        health: health.http("/xrpc/com.atproto.server.describeServer"),
        capabilities: [Cap.pds.describeServer],
        dependsOn: ["local-plc"],
      }),
    },
  });

  const raw = parseRawTopologyPresetV1({
    name: "typed-normalization",
    description: "Typed topology normalization",
    roles: {
      pds: {
        role: "pds",
        name: "typed-pds",
        image: "example/pds:latest",
        ports: [{ host: "2583", container: "2583", protocol: "tcp" }],
        volumes: [
          { kind: "named", source: "typed_pds_data", target: "/data" },
        ],
        healthCheck: {
          path: "/xrpc/com.atproto.server.describeServer",
        },
        capabilities: ["describeServer"],
        dependsOn: ["local-plc"],
      },
    },
  }, "inline");

  assertEquals(normalizeTopologyPreset(typed), normalizeTopologyPreset(raw));
});

Deno.test("defineTopology: source, port, and volume helpers normalize to raw schema", () => {
  const typed = defineTopology({
    name: "typed-helper-forms",
    description: "Typed helper forms",
    roles: {
      [Role.pds]: role.pds({
        name: "helper-pds",
        source: source.git({
          repo: "https://example.test/pds.git",
          ref: "main",
          dockerfile: "Dockerfile.pds",
        }),
        ports: [port({ host: 2583, container: 8080 })],
        volumes: [
          volume.bind("./fixtures", "/fixtures", "ro"),
          "helper_pds_data:/data",
        ],
        health: health.command(["CMD-SHELL", "test -f /tmp/ready"]),
        capabilities: [Cap.pds.describeServer],
      }),
      [Role.appview]: role.appview({
        name: "helper-appview",
        source: source.localBuild({
          buildContext: "docker/appview",
          dockerfile: "Dockerfile.local",
        }),
        health: health.none(),
        capabilities: [Cap.appview.getTimeline],
      }),
    },
  });

  const pds = typed.roles.pds;
  if (!pds || "inherit" in pds) throw new Error("pds should be concrete");
  assertEquals(pds.source?.repo, "https://example.test/pds.git");
  assertEquals(pds.ports, [{
    host: "2583",
    container: "8080",
    protocol: "tcp",
  }]);
  assertEquals(pds.volumes, [
    { kind: "bind", source: "./fixtures", target: "/fixtures", mode: "ro" },
    { kind: "named", source: "helper_pds_data", target: "/data" },
  ]);
  assertEquals(pds.healthCheck?.customTest, [
    "CMD-SHELL",
    "test -f /tmp/ready",
  ]);

  const appview = typed.roles.appview;
  if (!appview || "inherit" in appview) {
    throw new Error("appview should be concrete");
  }
  assertEquals(appview.buildContext, "docker/appview");
  assertEquals(appview.dockerfile, "Dockerfile.local");
  assertEquals(appview.healthCheck, { path: null });
});

Deno.test("dependsOnRoles: compiler resolves role dependencies to compose service names", async () => {
  const preset = defineTopology({
    name: "typed-role-dependencies",
    description: "Role dependency resolution",
    roles: {
      [Role.plc]: role.plc({
        name: "custom-plc",
        serviceName: "plc-under-test",
        source: source.image("example/plc:latest"),
        ports: [port(2582)],
        health: health.http("/_health"),
        capabilities: [Cap.plc.didResolution],
      }),
      [Role.pds]: role.pds({
        name: "dependency-pds",
        source: source.image("example/pds:latest"),
        ports: [port(2583)],
        health: health.http("/xrpc/com.atproto.server.describeServer"),
        capabilities: [Cap.pds.describeServer],
        dependsOnRoles: [Role.plc],
      }),
    },
  });
  TopologyRegistry.register(preset);

  const yaml = renderComposeYaml({
    name: preset.name,
    description: preset.description,
    roles: {
      plc: {
        name: "custom-plc",
        serviceName: "plc-under-test",
        image: "example/plc:latest",
        ports: ["2582:2582"],
        healthCheck: { path: "/_health" },
        capabilities: ["didResolution"],
      },
      pds: {
        name: "dependency-pds",
        image: "example/pds:latest",
        ports: ["2583:2583"],
        healthCheck: { path: "/xrpc/com.atproto.server.describeServer" },
        capabilities: ["describeServer"],
        dependsOnRoles: [Role.plc],
      },
    },
  }, {
    preset: preset.name,
    runDir: "/tmp/typed-role-dependencies",
    repoRoot: Deno.cwd(),
    composeProject: "test",
  });
  assertEquals(yaml.includes("depends_on:"), true);
  assertEquals(yaml.includes("plc-under-test:"), true);

  const runDir = await Deno.makeTempDir({ prefix: "typed-role-dependencies-" });
  try {
    const result = await compileTopology({
      preset: preset.name,
      runDir,
      repoRoot: Deno.cwd(),
      composeProject: "test",
    });
    assertEquals(result.manifest.services?.pds.dependencies.requested, ["plc"]);
    assertEquals(
      result.manifest.services?.pds.dependencies.composeServiceNames,
      [
        "plc-under-test",
      ],
    );
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});
