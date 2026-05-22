import { Command } from "@cliffy/command";
import { runSmoke } from "../smoke_command.ts";

export const smokeCommand = new Command()
  .description(
    "Run a smoke test against a local ATProto PDS.\n\n" +
      "Creates an account, posts, reads it back, and reports results.",
  )
  .option("--pds-url <url:string>", "PDS base URL.", {
    default: "http://localhost:2583",
  })
  .action(async ({ pdsUrl }) => {
    const result = await runSmoke(pdsUrl);
    console.log(result.summary());
    Deno.exit(result.ok ? 0 : 1);
  });
