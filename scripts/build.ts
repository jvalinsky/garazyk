#!/usr/bin/env -S deno run -A
import { buildCommandMain } from "@garazyk/narzedzia/build-command";
await buildCommandMain(Deno.args);
