/**
 * Tests for migration configuration schema and validator
 */

import { test } from "node:test";
import assert from "node:assert";
import {
  loadMigrationConfig,
  MigrationConfigError,
  migrationConfigSchema,
  validateMigrationConfig,
} from "./migration-schema.js";
import fs from "fs-extra";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test("migrationConfigSchema has required properties", () => {
  assert.strictEqual(migrationConfigSchema.type, "object");
  assert.ok(Array.isArray(migrationConfigSchema.required));
  assert.ok(migrationConfigSchema.required.includes("version"));
  assert.ok(migrationConfigSchema.required.includes("migrations"));
});

test("validateMigrationConfig rejects non-object input", () => {
  const result = validateMigrationConfig(null);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.length > 0);
});

test("validateMigrationConfig rejects missing required fields", () => {
  const config = {};
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("version")));
  assert.ok(result.errors.some((e) => e.includes("migrations")));
});

test("validateMigrationConfig rejects invalid version format", () => {
  const config = {
    version: "invalid",
    migrations: [],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("pattern")));
});

test("validateMigrationConfig rejects empty migrations array", () => {
  const config = {
    version: "1.0.0",
    migrations: [],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("at least 1")));
});

test("validateMigrationConfig rejects migration without source", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        destination: "docs/plans",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("source")));
});

test("validateMigrationConfig rejects migration without destination", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        source: "plan",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("destination")));
});

test("validateMigrationConfig rejects source === destination", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        source: "docs/plans",
        destination: "docs/plans",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("cannot be the same")));
});

test("validateMigrationConfig rejects destination inside source", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        source: "docs",
        destination: "docs/plans",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("inside source")));
});

test("validateMigrationConfig rejects source inside destination", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        source: "docs/plans",
        destination: "docs",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("inside destination")));
});

test("validateMigrationConfig rejects duplicate source directories", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        source: "plan",
        destination: "docs/plans",
      },
      {
        source: "plan",
        destination: "docs/archive",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("duplicate source")));
});

test("validateMigrationConfig rejects unexpected properties", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        source: "plan",
        destination: "docs/plans",
        unexpectedProp: "value",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, false);
  assert.ok(result.errors.some((e) => e.includes("unexpected property")));
});

test("validateMigrationConfig accepts valid minimal config", () => {
  const config = {
    version: "1.0.0",
    migrations: [
      {
        source: "plan",
        destination: "docs/plans",
      },
    ],
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, true);
  assert.strictEqual(result.errors.length, 0);
});

test("validateMigrationConfig accepts valid full config", () => {
  const config = {
    version: "1.0.0",
    description: "Test migration",
    migrations: [
      {
        source: "plan",
        destination: "docs/plans",
        filePatterns: ["**/*.md"],
        excludePatterns: ["**/.git/**"],
        preserveStructure: true,
        updateReferences: true,
        removeEmptyDirs: true,
      },
    ],
    options: {
      dryRun: false,
      verbose: true,
      generateReport: true,
      reportPath: "report.json",
      mappingPath: "mapping.json",
      continueOnError: false,
    },
  };
  const result = validateMigrationConfig(config);
  assert.strictEqual(result.valid, true);
  assert.strictEqual(result.errors.length, 0);
});

test("loadMigrationConfig throws on non-existent file", async () => {
  await assert.rejects(
    async () => {
      await loadMigrationConfig("/nonexistent/config.json");
    },
    MigrationConfigError,
  );
});

test("loadMigrationConfig throws on invalid JSON", async () => {
  const tempFile = path.join(__dirname, "../test-temp-invalid.json");
  await fs.writeFile(tempFile, "invalid json{", "utf8");

  try {
    await assert.rejects(
      async () => {
        await loadMigrationConfig(tempFile);
      },
      MigrationConfigError,
    );
  } finally {
    await fs.remove(tempFile);
  }
});

test("loadMigrationConfig throws on invalid config", async () => {
  const tempFile = path.join(__dirname, "../test-temp-invalid-config.json");
  await fs.writeFile(tempFile, JSON.stringify({ version: "invalid" }), "utf8");

  try {
    await assert.rejects(
      async () => {
        await loadMigrationConfig(tempFile);
      },
      MigrationConfigError,
    );
  } finally {
    await fs.remove(tempFile);
  }
});

test("loadMigrationConfig loads and applies defaults", async () => {
  const tempFile = path.join(__dirname, "../test-temp-valid.json");
  const minimalConfig = {
    version: "1.0.0",
    migrations: [
      {
        source: "plan",
        destination: "docs/plans",
      },
    ],
  };
  await fs.writeFile(tempFile, JSON.stringify(minimalConfig), "utf8");

  try {
    const config = await loadMigrationConfig(tempFile);

    // Check defaults were applied to migration
    assert.ok(Array.isArray(config.migrations[0].filePatterns));
    assert.ok(Array.isArray(config.migrations[0].excludePatterns));
    assert.strictEqual(config.migrations[0].preserveStructure, true);
    assert.strictEqual(config.migrations[0].updateReferences, true);
    assert.strictEqual(config.migrations[0].removeEmptyDirs, true);

    // Check defaults were applied to options
    assert.strictEqual(config.options.dryRun, false);
    assert.strictEqual(config.options.verbose, false);
    assert.strictEqual(config.options.generateReport, true);
    assert.strictEqual(config.options.reportPath, "migration-report.json");
    assert.strictEqual(config.options.mappingPath, "migration-mapping.json");
    assert.strictEqual(config.options.continueOnError, false);
  } finally {
    await fs.remove(tempFile);
  }
});

test("loadMigrationConfig preserves explicit values", async () => {
  const tempFile = path.join(__dirname, "../test-temp-explicit.json");
  const explicitConfig = {
    version: "1.0.0",
    migrations: [
      {
        source: "plan",
        destination: "docs/plans",
        filePatterns: ["**/*.txt"],
        preserveStructure: false,
      },
    ],
    options: {
      verbose: true,
      reportPath: "custom-report.json",
    },
  };
  await fs.writeFile(tempFile, JSON.stringify(explicitConfig), "utf8");

  try {
    const config = await loadMigrationConfig(tempFile);

    // Check explicit values were preserved
    assert.deepStrictEqual(config.migrations[0].filePatterns, ["**/*.txt"]);
    assert.strictEqual(config.migrations[0].preserveStructure, false);
    assert.strictEqual(config.options.verbose, true);
    assert.strictEqual(config.options.reportPath, "custom-report.json");

    // Check other defaults were still applied
    assert.strictEqual(config.options.dryRun, false);
  } finally {
    await fs.remove(tempFile);
  }
});

test("example config file is valid", async () => {
  const exampleConfigPath = path.join(__dirname, "../configs/plan-consolidation.json");

  // Check if example config exists
  const exists = await fs.pathExists(exampleConfigPath);
  if (!exists) {
    // Skip test if example config doesn't exist yet
    return;
  }

  // Load and validate example config
  const config = await loadMigrationConfig(exampleConfigPath);
  assert.ok(config);
  assert.strictEqual(config.version, "1.0.0");
  assert.ok(Array.isArray(config.migrations));
  assert.ok(config.migrations.length > 0);
});
