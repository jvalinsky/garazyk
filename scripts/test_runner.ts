#!/usr/bin/env -S deno run -A
import { testCommandMain } from "@garazyk/hamownia/test-command";
await testCommandMain(Deno.args);
