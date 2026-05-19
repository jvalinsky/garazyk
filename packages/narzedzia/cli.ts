import { Command } from "@cliffy/command";
import { CompletionsCommand } from "@cliffy/command/completions";
import { HelpCommand } from "@cliffy/command/help";
import { opsCommand } from "./cli/ops.ts";

export const narzedziaCommand = new Command()
  .name("narzedzia")
  .version("1.0.0")
  .description(
    "Garazyk production operations.\n\n" +
    "WARNING: These commands affect production systems. " +
    "They require explicit paths and tokens — no sensible defaults.",
  )
  .globalOption("-v, --verbose", "Enable verbose logging.")
  .globalOption("-q, --quiet", "Suppress non-error output.")
  .command("ops", opsCommand)
  .command("help", new HelpCommand().global())
  .command("completions", new CompletionsCommand().global());

if (import.meta.main) {
  await narzedziaCommand.parse(Deno.args);
}
