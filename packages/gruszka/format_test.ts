import { assertEquals } from "@std/assert";
import { formatBytes } from "./format.ts";

Deno.test("formatBytes: zero", () => {
  assertEquals(formatBytes(0), "0 B");
});

Deno.test("formatBytes: one byte", () => {
  assertEquals(formatBytes(1), "1 B");
});

Deno.test("formatBytes: below 1 KiB", () => {
  assertEquals(formatBytes(512), "512 B");
});

Deno.test("formatBytes: exactly 1 KiB", () => {
  assertEquals(formatBytes(1024), "1.0 KiB");
});

Deno.test("formatBytes: 1.5 KiB", () => {
  assertEquals(formatBytes(1536), "1.5 KiB");
});

Deno.test("formatBytes: exactly 1 MiB", () => {
  assertEquals(formatBytes(1024 * 1024), "1.0 MiB");
});

Deno.test("formatBytes: 2.3 MiB", () => {
  assertEquals(formatBytes(2.3 * 1024 * 1024), "2.3 MiB");
});

Deno.test("formatBytes: exactly 1 GiB", () => {
  assertEquals(formatBytes(1024 * 1024 * 1024), "1.0 GiB");
});

Deno.test("formatBytes: 4.7 GiB", () => {
  assertEquals(formatBytes(4.7 * 1024 * 1024 * 1024), "4.7 GiB");
});

Deno.test("formatBytes: exactly 1 TiB", () => {
  assertEquals(formatBytes(1024 * 1024 * 1024 * 1024), "1.0 TiB");
});

Deno.test("formatBytes: 2.5 TiB", () => {
  assertEquals(formatBytes(2.5 * 1024 * 1024 * 1024 * 1024), "2.5 TiB");
});

Deno.test("formatBytes: bytes show no decimal", () => {
  assertEquals(formatBytes(999), "999 B");
});
