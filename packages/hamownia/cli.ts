import { Command } from "@cliffy/command";
import { CompletionsCommand } from "@cliffy/command/completions";
import { HelpCommand } from "@cliffy/command/help";
import { demoCommand } from "./cli/demo.ts";
import { fuzzCommand } from "./cli/fuzz.ts";
import { runCommand } from "./cli/run.ts";
import { serviceCommand } from "./cli/service.ts";
import { smokeCommand } from "./cli/smoke.ts";
import { testCommand } from "./cli/test.ts";

export const hamowniaCommand = new Command()
  .name("hamownia")
  .version("1.0.0")
  .description(
    "Garazyk developer tooling.\n\n" +
    "Manage local ATProto services, run e2e scenarios, " +
    "start the full demo stack, smoke-test, and fuzz.",
  )
  .globalOption("-v, --verbose", "Enable verbose logging.")
  .globalOption("-q, --quiet", "Suppress non-error output.")
  .command("service", serviceCommand)
  .command("demo", demoCommand)
  .command("fuzz", fuzzCommand)
  .command("run", runCommand)
  .command("smoke", smokeCommand)
  .command("test", testCommand)
  .command("help", new HelpCommand().global())
  .command("completions", new CompletionsCommand().global());

if (import.meta.main) {
  await hamowniaCommand.parse(Deno.args);
}
