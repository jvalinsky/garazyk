import { assert, assertEquals } from "@std/assert";
import { addSpdxHeader, hasSpdx } from "./spdx_headers.ts";

const DEFAULT_HEADER =
  "// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky\n" +
  "// SPDX-License-Identifier: Unlicense OR CC0-1.0\n";

const YEAR_2024_HEADER =
  "// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky\n" +
  "// SPDX-License-Identifier: Unlicense OR CC0-1.0\n";

const MSTWALKER_ATTRIBUTION =
  "// Based on https://github.com/bluesky-social/atproto (MIT OR Apache-2.0)\n";

Deno.test("hasSpdx returns true when SPDX line is present", () => {
  assert(hasSpdx("// SPDX-License-Identifier: Unlicense OR CC0-1.0\nconst x = 1;"));
});

Deno.test("hasSpdx returns true when SPDX line appears later in content", () => {
  assert(hasSpdx("const x = 1;\n// SPDX-License-Identifier: Unlicense OR CC0-1.0\n"));
});

Deno.test("hasSpdx returns false when SPDX line is absent", () => {
  assert(!hasSpdx("const x = 1;\nconsole.log(x);\n"));
});

Deno.test("addSpdxHeader prepends the default SPDX header", () => {
  assertEquals(addSpdxHeader("const answer = 42;\n", "packages/narzedzia/example.ts"),
    DEFAULT_HEADER + "const answer = 42;\n");
});

Deno.test("addSpdxHeader preserves multiline content after the header", () => {
  const content = "export function run() {\n  return true;\n}\n";
  assertEquals(addSpdxHeader(content, "packages/narzedzia/example.ts"),
    DEFAULT_HEADER + content);
});

Deno.test("addSpdxHeader uses the 2025-2026 header for ordinary paths", () => {
  assertEquals(addSpdxHeader("body\n", "Garazyk/Sources/Other/File.m"),
    DEFAULT_HEADER + "body\n");
});

Deno.test("addSpdxHeader uses the 2024-2026 header for selected 2024 files", () => {
  assertEquals(addSpdxHeader("body\n", "Garazyk/Sources/Auth/JWT.m"),
    YEAR_2024_HEADER + "body\n");
});

Deno.test("addSpdxHeader adds MSTWalker attribution when the path contains MSTWalker", () => {
  assertEquals(addSpdxHeader("body\n", "Garazyk/Sources/MSTWalker/Tool.ts"),
    DEFAULT_HEADER + MSTWALKER_ATTRIBUTION + "body\n");
});

Deno.test("addSpdxHeader handles empty content", () => {
  assertEquals(addSpdxHeader("", "Garazyk/Sources/Other/File.m"), DEFAULT_HEADER);
});

Deno.test("addSpdxHeader prepends a header even when content already has one", () => {
  const existing =
    "// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky\n" +
    "// SPDX-License-Identifier: Unlicense OR CC0-1.0\n" +
    "const value = 1;\n";

  assertEquals(
    addSpdxHeader(existing, "Garazyk/Sources/Other/File.m"),
    DEFAULT_HEADER + existing,
  );
});

Deno.test("addSpdxHeader preserves the original SPDX header text verbatim", () => {
  const existing =
    "// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky\n" +
    "// SPDX-License-Identifier: Unlicense OR CC0-1.0\n";

  const result = addSpdxHeader(existing, "Garazyk/Sources/Auth/JWT.m");

  assert(result.startsWith(YEAR_2024_HEADER));
  assert(result.endsWith(existing));
});
