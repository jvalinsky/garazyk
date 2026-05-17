#!/usr/bin/env node

/**
 * Migration Configuration Validator
 *
 * Validates migration configuration files against the schema.
 *
 * Usage: node validate-config.js <config-file>
 */

import { loadMigrationConfig, MigrationConfigError } from "./lib/migration-schema.js";
import { version } from "./index.js";

const configPath = process.argv[2];

if (!configPath) {
  console.error("Usage: node validate-config.js <config-file>");
  process.exit(1);
}

console.log(`Migration Configuration Validator v${version}`);
console.log(`Validating: ${configPath}\n`);

try {
  const config = await loadMigrationConfig(configPath);

  console.log("✓ Configuration is valid\n");
  console.log("Summary:");
  console.log(`  Version: ${config.version}`);
  if (config.description) {
    console.log(`  Description: ${config.description}`);
  }
  console.log(`  Migrations: ${config.migrations.length}`);

  config.migrations.forEach((migration, index) => {
    console.log(`\n  Migration ${index + 1}:`);
    console.log(`    Source: ${migration.source}`);
    console.log(`    Destination: ${migration.destination}`);
    console.log(`    File patterns: ${migration.filePatterns.length}`);
    console.log(`    Exclude patterns: ${migration.excludePatterns.length}`);
    console.log(`    Preserve structure: ${migration.preserveStructure}`);
    console.log(`    Update references: ${migration.updateReferences}`);
    console.log(`    Remove empty dirs: ${migration.removeEmptyDirs}`);
  });

  console.log("\n  Options:");
  console.log(`    Dry run: ${config.options.dryRun}`);
  console.log(`    Verbose: ${config.options.verbose}`);
  console.log(`    Generate report: ${config.options.generateReport}`);
  console.log(`    Report path: ${config.options.reportPath}`);
  console.log(`    Mapping path: ${config.options.mappingPath}`);
  console.log(`    Continue on error: ${config.options.continueOnError}`);

  process.exit(0);
} catch (error) {
  if (error instanceof MigrationConfigError) {
    console.error("✗ Configuration validation failed\n");
    console.error(`Error: ${error.message}`);

    if (error.errors && error.errors.length > 0) {
      console.error("\nValidation errors:");
      error.errors.forEach((err) => {
        console.error(`  - ${err}`);
      });
    }
  } else {
    console.error("✗ Unexpected error\n");
    console.error(error);
  }

  process.exit(1);
}
