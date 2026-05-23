// scratch_run_beskid.ts
import { delay } from "https://deno.land/std@0.224.0/async/delay.ts";

try {
  Deno.removeSync("/tmp/beskid-test.db");
} catch {}
try {
  Deno.removeSync("/tmp/beskid-test", { recursive: true });
} catch {}

try {
  const killCmd = new Deno.Command("killall", { args: ["-9", "beskid"] });
  const { code } = killCmd.outputSync();
  if (code === 0) console.log("Killed dangling beskid process.");
} catch {}

console.log("Starting Beskid daemon...");
const beskidCmd = new Deno.Command("./build/bin/beskid", {
  args: ["serve"],
  env: {
    BESKID_HTTP_PORT: "8085",
    BESKID_DATA_DIR: "/tmp/beskid-test",
    BESKID_DATABASE_PATH: "/tmp/beskid-test.db",
    PDS_LISTEN_HOST: "127.0.0.1",
    PDS_ALLOW_PRIVATE_HOSTS: "1",
    PDS_PLC_URL: "http://127.0.0.1:2582"
  },
  stdout: "piped",
  stderr: "piped"
});

const beskidProcess = beskidCmd.spawn();

(async () => {
  try {
    const reader = beskidProcess.stdout.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      await Deno.stdout.write(value);
    }
  } catch (e) {
    console.error("stdout reader error:", e);
  }
})();

(async () => {
  try {
    const readerErr = beskidProcess.stderr.getReader();
    while (true) {
      const { done, value } = await readerErr.read();
      if (done) break;
      await Deno.stderr.write(value);
    }
  } catch (e) {
    console.error("stderr reader error:", e);
  }
})();

console.log("Waiting 2s for Beskid to initialize...");
await delay(2000);

console.log("Running scenario 69...");
const scenarioCmd = new Deno.Command("deno", {
  args: ["run", "-A", "scripts/run_scenarios.ts", "--binary", "69"],
  env: {
    BESKID_URL: "http://127.0.0.1:8085"
  },
  stdout: "inherit",
  stderr: "inherit"
});

const scenarioProcess = scenarioCmd.spawn();
const status = await scenarioProcess.status;
console.log("Scenario runner exited with code", status.code);

console.log("Shutting down Beskid daemon...");
try {
  beskidProcess.kill("SIGTERM");
} catch (e) {
  console.log("Error killing Beskid:", e);
}

Deno.exit(status.code);
