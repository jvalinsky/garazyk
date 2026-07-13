#!/usr/bin/env -S deno run -A
import { dirname, fromFileUrl, join } from "$std/path/mod.ts";
import dev from "$fresh/dev.ts";
import { getDashboardSecurity } from "./services/dashboard_security.ts";

const dir = dirname(fromFileUrl(import.meta.url));
const security = getDashboardSecurity();

await dev(import.meta.url, "fresh.gen.ts", {
  plugins: [],
  staticDir: join(dir, "static"),
  router: {
    trailingSlash: false,
  },
  server: { hostname: security.host, port: security.port },
});
