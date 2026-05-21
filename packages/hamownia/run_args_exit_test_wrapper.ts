/**
 * Thin wrapper that calls parseRunnerArgs(Deno.args) and exits.
 * Used by run_command_test.ts subprocess tests to verify Deno.exit(2) paths.
 */
import { parseRunnerArgs } from "./run_command.ts";

parseRunnerArgs(Deno.args);
