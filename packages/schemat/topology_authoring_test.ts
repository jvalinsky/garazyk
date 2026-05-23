import { assertEquals } from "@std/assert";
import {
  Cap,
  defineTopology,
  health,
  port,
  requires,
  Role,
  role,
  serviceRef,
  source,
  TopologyRegistry,
  volume,
} from "./mod.ts";
import { compileTopology, renderComposeYaml } from "./topology_compiler.ts";

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

function compileTimeRawAuthoringRejections(): void {
  const stringPortPreset = defineTopology({
    name: "string-port-authoring",
    description: "String ports are rejected by typed authoring",
    roles: {
      [Role.pds]: role.pds({
        name: "bad-pds",
        source: source.image("example/pds:latest"),
        // @ts-expect-error string port mappings must use port(...).
        ports: ["2583:2583"],
        health: health.http("/xrpc/com.atproto.server.describeServer"),
        capabilities: [Cap.pds.describeServer],
      }),
    },
  });
  void stringPortPreset;

  const stringVolumePreset = defineTopology({
    name: "string-volume-authoring",
    description: "String volumes are rejected by typed authoring",
    roles: {
      [Role.pds]: role.pds({
        name: "bad-pds",
        source: source.image("example/pds:latest"),
        ports: [port(2583)],
        // @ts-expect-error string volume mappings must use volume.*(...).
        volumes: ["pds_data:/data"],
        health: health.http("/xrpc/com.atproto.server.describeServer"),
        capabilities: [Cap.pds.describeServer],
      }),
    },
  });
  void stringVolumePreset;

  const rawHealthPreset = defineTopology({
    name: "raw-health-authoring",
    description: "Raw healthCheck is rejected by typed authoring",
    roles: {
      [Role.pds]: role.pds({
        name: "bad-pds",
        source: source.image("example/pds:latest"),
        ports: [port(2583)],
        // @ts-expect-error typed authoring uses health: health.*(...).
        healthCheck: { path: "/xrpc/com.atproto.server.describeServer" },
        capabilities: [Cap.pds.describeServer],
      }),
    },
  });
  void rawHealthPreset;

  const rawImagePreset = defineTopology({
    name: "raw-image-authoring",
    description: "Raw image is rejected by typed authoring",
    roles: {
      [Role.pds]: role.pds({
        name: "bad-pds",
        // @ts-expect-error typed authoring uses source: source.image(...).
        image: "example/pds:latest",
        ports: [port(2583)],
        health: health.http("/xrpc/com.atproto.server.describeServer"),
        capabilities: [Cap.pds.describeServer],
      }),
    },
  });
  void rawImagePreset;

  const rawBuildContextPreset = defineTopology({
    name: "raw-build-context-authoring",
    description: "Raw buildContext is rejected by typed authoring",
    roles: {
      [Role.pds]: role.pds({
        name: "bad-pds",
        // @ts-expect-error typed authoring uses source: source.localBuild(...).
        buildContext: "docker/local-network",
        ports: [port(2583)],
        health: health.http("/xrpc/com.atproto.server.describeServer"),
        capabilities: [Cap.pds.describeServer],
      }),
    },
  });
  void rawBuildContextPreset;

  const rawDependsOnPreset = defineTopology({
    name: "raw-depends-on-authoring",
    description: "Raw dependsOn strings are rejected by typed authoring",
    roles: {
      [Role.pds]: role.pds({
        name: "bad-pds",
        source: source.image("example/pds:latest"),
        ports: [port(2583)],
        health: health.http("/xrpc/com.atproto.server.describeServer"),
        capabilities: [Cap.pds.describeServer],
        // @ts-expect-error direct service dependencies must use serviceRef(...).
        dependsOn: ["local-plc"],
      }),
    },
  });
  void rawDependsOnPreset;

  // @ts-expect-error registry registration accepts normalized typed presets only.
  TopologyRegistry.register({
    name: "raw-registration",
    description: "Raw registry registration is rejected",
    roles: {},
  });
}
void compileTimeRawAuthoringRejections;

Deno.test("defineTopology: typed service returns registry-ready normalized preset", () => {
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
        dependsOn: [serviceRef("local-plc")],
      }),
    },
  });

  const pds = typed.roles.pds;
  if (!pds || "inherit" in pds) throw new Error("pds should be concrete");
  assertEquals(typed.name, "typed-normalization");
  assertEquals(pds.image, "example/pds:latest");
  assertEquals(pds.dependsOn, ["local-plc"]);
});

Deno.test("defineTopology: Beskid role exposes typed capabilities", () => {
  const typed = defineTopology({
    name: "typed-beskid",
    description: "Beskid topology role",
    roles: {
      [Role.beskid]: role.beskid({
        name: "beskid",
        source: source.image("example/beskid:latest"),
        ports: [port(8085)],
        health: health.http("/_health"),
        capabilities: [
          Cap.beskid.getUriRecord,
          Cap.beskid.resolveHandle,
          Cap.beskid.hydrateQueryResponse,
          Cap.beskid.recordCache,
        ],
      }),
    },
  });

  const beskid = typed.roles.beskid;
  if (!beskid || "inherit" in beskid) {
    throw new Error("beskid should be concrete");
  }
  assertEquals(beskid.ports, [{
    host: "8085",
    container: "8085",
    protocol: "tcp",
  }]);
  assertEquals(beskid.capabilities.includes("hydrateQueryResponse"), true);
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
          volume.named("helper_pds_data", "/data"),
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
  assertEquals(pds.health, {
    type: "command",
    customTest: [
      "CMD-SHELL",
      "test -f /tmp/ready",
    ],
    timeoutSeconds: 60,
  });

  const appview = typed.roles.appview;
  if (!appview || "inherit" in appview) {
    throw new Error("appview should be concrete");
  }
  assertEquals(appview.buildContext, "docker/appview");
  assertEquals(appview.dockerfile, "Dockerfile.local");
  assertEquals(appview.health, undefined);
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
