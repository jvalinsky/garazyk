import { assertEquals } from "@std/assert";
import {
  ContainerEventWatcher,
  DockerApiClient,
  waitForHttp,
} from "./mod.ts";

Deno.test("laweta root exposes generic Docker primitives", () => {
  assertEquals(typeof DockerApiClient, "function");
  assertEquals(typeof ContainerEventWatcher.create, "function");
  assertEquals(typeof waitForHttp, "function");
});
