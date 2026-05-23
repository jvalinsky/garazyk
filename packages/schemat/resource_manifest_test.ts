import { assertEquals } from "@std/assert";
import {
  applyRunResourceEnvironment,
  createRunResourceManifest,
  loadRunResourceManifest,
  mockProviderUrlsFromResourceManifest,
  serviceUrlsFromResourceManifest,
  writeRunResourceManifest,
} from "./resource_manifest.ts";

Deno.test("resource manifest writes, loads, and exports service URLs", async () => {
  const dir = await Deno.makeTempDir({ prefix: "resource-manifest-test-" });
  const path = `${dir}/resource-manifest.json`;
  const manifest = createRunResourceManifest({
    runId: "run-a",
    runDir: dir,
    composeProject: "garazyk-e2e-run-a",
  });
  manifest.services.pds = {
    role: "pds",
    hostPort: 34567,
    hostUrl: "http://127.0.0.1:34567",
  };
  manifest.mockProviders = {
    twilio: {
      role: "twilio",
      hostPort: 34568,
      hostUrl: "http://127.0.0.1:34568",
    },
  };

  try {
    await writeRunResourceManifest(path, manifest);
    const loaded = loadRunResourceManifest(path)!;
    assertEquals(loaded.runId, "run-a");
    assertEquals(serviceUrlsFromResourceManifest(loaded), {
      pds: "http://127.0.0.1:34567",
    });
    assertEquals(mockProviderUrlsFromResourceManifest(loaded), {
      twilio: "http://127.0.0.1:34568",
    });

    const env: Record<string, string> = {};
    applyRunResourceEnvironment(loaded, {
      set(key, value) {
        env[key] = value;
      },
    });
    assertEquals(env.PDS_URL, "http://127.0.0.1:34567");
    assertEquals(env.TWILIO_API_BASE_URL, "http://127.0.0.1:34568");
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
