#!/usr/bin/env -S deno run --allow-read --allow-write

/**
 * Compatibility launcher for the Gruszka lexicon generator.
 *
 * The package generator owns discovery, validation, and rendering so every
 * entry point uses the canonical Garazyk/Resources/lexicons inventory.
 */

import { generateLexicons } from "../packages/gruszka/scripts/generate.ts";

if (import.meta.main) {
  try {
    const result = await generateLexicons();
    console.log(
      `Wrote ${result.lexiconCount} lexicons (${result.endpointCount} endpoints) to ${result.outFile}`,
    );
  } catch (error) {
    console.error("Generation failed:", error);
    Deno.exit(1);
  }
}
