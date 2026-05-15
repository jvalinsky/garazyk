import { assertEquals } from "jsr:@std/assert";

Deno.test("PDS2 compose port mapping, health check, and config use port 2587", async () => {
  const compose = await Deno.readTextFile("docker/local-network/docker-compose.scenarios.yml");
  const config = JSON.parse(await Deno.readTextFile("docker/local-network/pds2-config.json"));

  assertEquals(config.server.port, 2587);
  assertEquals(compose.includes('"2587:2587"'), true);
  assertEquals(
    compose.includes("http://localhost:2587/xrpc/com.atproto.server.describeServer"),
    true,
  );
});
