#!/usr/bin/env -S deno run -A
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

import { dirname, fromFileUrl, join } from "$std/path/mod.ts";
import { start } from "$fresh/server.ts";
import manifest from "./fresh.gen.ts";
import { SKYLAB_PORT } from "./services/config.ts";

const dir = dirname(fromFileUrl(import.meta.url));

await start(manifest, {
  plugins: [],
  staticDir: join(dir, "static"),
  router: {
    basePath: "/skylab",
    trailingSlash: false,
  },
  server: { port: SKYLAB_PORT },
});
