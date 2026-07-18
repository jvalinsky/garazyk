/** Tests for hamownia/actor.ts — Actor and ActorFactory. @module actor_test */

import { assertEquals, assertMatch } from "@std/assert";
import { Actor, ActorFactory } from "./actor.ts";
import type { ActorTemplate } from "./actor.ts";

// ── Actor ───────────────────────────────────────────────────────────────

Deno.test("Actor: constructor sets all fields", () => {
  const actor = new Actor(
    "Alice",
    "alice.test.example",
    "alice@test.com",
    "secret",
    "admin persona",
    "admin",
    "http://localhost:2583",
  );

  assertEquals(actor.name, "Alice");
  assertEquals(actor.handle, "alice.test.example");
  assertEquals(actor.email, "alice@test.com");
  assertEquals(actor.password, "secret");
  assertEquals(actor.persona, "admin persona");
  assertEquals(actor.role, "admin");
  assertEquals(actor.pdsUrl, "http://localhost:2583");
});

Deno.test("Actor: default role is user and default pdsUrl is empty", () => {
  const actor = new Actor("Bob", "bob", "bob@test.com", "pw", "persona");

  assertEquals(actor.role, "user");
  assertEquals(actor.pdsUrl, "");
});

Deno.test("Actor: token getter returns accessJwt", () => {
  const actor = new Actor("C", "c", "c@t", "p", "per");
  assertEquals(actor.token, "");

  actor.accessJwt = "jwt-abc";
  assertEquals(actor.token, "jwt-abc");
});

Deno.test("Actor: did, accessJwt, refreshJwt start empty", () => {
  const actor = new Actor("D", "d", "d@t", "p", "per");
  assertEquals(actor.did, "");
  assertEquals(actor.accessJwt, "");
  assertEquals(actor.refreshJwt, "");
});

// ── ActorFactory ────────────────────────────────────────────────────────

const template: ActorTemplate = {
  name: "TestUser",
  handle: "testuser.example",
  email: "test@example.com",
  password: "pass123",
  persona: "tester",
  role: "mod",
  pds: "pds1",
};

Deno.test("ActorFactory: createFromTemplate produces Actor with correct fields", () => {
  const factory = new ActorFactory("http://pds1:2583", "http://pds2:2587");
  const actor = factory.createFromTemplate(template);

  assertEquals(actor instanceof Actor, true);
  assertEquals(actor.name, "TestUser");
  assertEquals(actor.password, "pass123");
  assertEquals(actor.persona, "tester");
  assertEquals(actor.role, "mod");
  assertEquals(actor.pdsUrl, "http://pds1:2583");
});

Deno.test("ActorFactory: pds2 template assigns pds2 URL", () => {
  const factory = new ActorFactory("http://pds1:2583", "http://pds2:2587");
  const actor = factory.createFromTemplate({ ...template, pds: "pds2" });

  assertEquals(actor.pdsUrl, "http://pds2:2587");
});

Deno.test("ActorFactory: handles from different factories have unique suffixes", () => {
  const factoryA = new ActorFactory();
  const factoryB = new ActorFactory();
  const a = factoryA.createFromTemplate(template);
  const b = factoryB.createFromTemplate(template);

  assertMatch(a.handle, /^testuser-[^.]+\.example$/);
  assertMatch(b.handle, /^testuser-[^.]+\.example$/);
  assertEquals(a.handle === b.handle, false);
});

Deno.test("ActorFactory: emails from different factories have unique suffixes", () => {
  const factoryA = new ActorFactory();
  const factoryB = new ActorFactory();
  const a = factoryA.createFromTemplate(template);
  const b = factoryB.createFromTemplate(template);

  assertMatch(a.email, /^test-[^@]+@example\.com$/);
  assertMatch(b.email, /^test-[^@]+@example\.com$/);
  assertEquals(a.email === b.email, false);
});

Deno.test("ActorFactory: single-part handle gets suffix appended", () => {
  const factory = new ActorFactory();
  const actor = factory.createFromTemplate({
    ...template,
    handle: "simplehandle",
  });

  assertMatch(actor.handle, /^simplehandle-[^.]+$/);
});

Deno.test("ActorFactory: default PDS URLs", () => {
  const factory = new ActorFactory();
  const pds1 = factory.createFromTemplate({ ...template, pds: "pds1" });
  const pds2 = factory.createFromTemplate({ ...template, pds: "pds2" });

  assertEquals(pds1.pdsUrl, "http://localhost:2583");
  assertEquals(pds2.pdsUrl, "http://localhost:2587");
});

Deno.test("ActorFactory: suffix uses PID and hex counter", () => {
  const factory = new ActorFactory();
  const actor = factory.createFromTemplate(template);

  // Suffix format: <pid>-<hex padded to 4 chars>
  assertMatch(actor.handle, new RegExp(`testuser-${Deno.pid}-[0-9a-f]{4}\\.example`));
});
