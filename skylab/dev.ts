#!/usr/bin/env -S deno run -A
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

import { dirname, fromFileUrl, join } from "$std/path/mod.ts";
import dev from "$fresh/dev.ts";
import { SKYLAB_PORT } from "./services/config.ts";

const dir = dirname(fromFileUrl(import.meta.url));

await dev(import.meta.url, "fresh.gen.ts", {
  plugins: [],
  staticDir: join(dir, "static"),
  router: {
    basePath: "/skylab",
    trailingSlash: false,
  },
  server: { port: SKYLAB_PORT },
});
