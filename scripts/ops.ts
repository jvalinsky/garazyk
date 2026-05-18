#!/usr/bin/env -S deno run -A
import { opsCommandMain } from "@garazyk/narzedzia/ops-command";
await opsCommandMain(Deno.args);
