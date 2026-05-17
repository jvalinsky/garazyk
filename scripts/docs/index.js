/**
 * Documentation Tooling Entry Point
 *
 * This module provides the main entry point for the documentation
 * consolidation and validation tooling.
 */

export const version = "1.0.0";

/**
 * Main entry point for CLI usage
 */
export function main() {
  console.log("Garazyk Documentation Tooling");
  console.log(`Version: ${version}`);
  console.log("\nAvailable commands:");
  console.log("  npm run migrate  - Consolidate documentation");
  console.log("  npm run validate - Validate documentation quality");
  console.log("  npm run archive  - Archive outdated documentation");
}

// Run main if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
