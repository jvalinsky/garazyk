#!/usr/bin/env -S deno run -A
import { serviceCommandMain } from "@garazyk/hamownia/service-command";
await serviceCommandMain(Deno.args);
