#!/usr/bin/env -S deno run -A
import { fuzzCommandMain } from "@garazyk/narzedzia/fuzz-command";
await fuzzCommandMain(Deno.args);
