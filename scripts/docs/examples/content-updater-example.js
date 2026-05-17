#!/usr/bin/env node

/**
 * Content Updater Example
 *
 * Demonstrates how to use the content updater to update links in Markdown files
 * when files are moved during documentation consolidation.
 */

import fs from "fs/promises";
import path from "path";
import os from "os";
import {
  updateFileLinks,
  updateLinksInContent,
  updateMultipleFiles,
  validateFileForUpdate,
} from "../lib/content-updater.js";

// ============================================================================
// Example 1: Update links in content string
// ============================================================================

console.log("Example 1: Update links in content string");
console.log("=".repeat(60));

const content = `
# Documentation

See the [installation guide](./guides/install.md) for setup.

## Links

- [API Reference](../api/reference.md)
- [Examples](./examples/basic.md)

[guide]: ./guides/advanced.md

Check the [advanced guide][guide].
`;

// Create a path mapping for links that need to be updated
const pathMap = new Map([
  ["./guides/install.md", "../guides/install.md"],
  ["../api/reference.md", "../../api/reference.md"],
  ["./examples/basic.md", "../examples/basic.md"],
  ["./guides/advanced.md", "../guides/advanced.md"],
]);

const updatedContent = updateLinksInContent(content, pathMap);

console.log("Original content:");
console.log(content);
console.log("\nUpdated content:");
console.log(updatedContent);
console.log();

// ============================================================================
// Example 2: Update links in a file
// ============================================================================

console.log("Example 2: Update links in a file");
console.log("=".repeat(60));

async function updateFileExample() {
  // Create a temporary file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-example-"));
  const filePath = path.join(tempDir, "test.md");

  const fileContent = `
# My Documentation

Check out these resources:
- [Getting Started](./getting-started.md)
- [API Docs](./api/index.md)
- [Examples](./examples/basic.md)
`;

  await fs.writeFile(filePath, fileContent, "utf8");

  console.log("Created file:", filePath);
  console.log("Original content:");
  console.log(fileContent);

  // Update links in the file
  const filePathMap = new Map([
    ["./getting-started.md", "../getting-started.md"],
    ["./api/index.md", "../api/index.md"],
    ["./examples/basic.md", "../examples/basic.md"],
  ]);

  const result = await updateFileLinks(filePath, filePathMap);

  console.log("\nUpdate result:");
  console.log("- Updated:", result.updated);
  console.log("- Changes count:", result.changesCount);

  const updatedFileContent = await fs.readFile(filePath, "utf8");
  console.log("\nUpdated content:");
  console.log(updatedFileContent);

  // Clean up
  await fs.rm(tempDir, { recursive: true, force: true });
  console.log("\nCleaned up temporary directory");
}

await updateFileExample();
console.log();

// ============================================================================
// Example 3: Update multiple files
// ============================================================================

console.log("Example 3: Update multiple files");
console.log("=".repeat(60));

async function updateMultipleFilesExample() {
  // Create temporary files
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-example-"));

  const file1Path = path.join(tempDir, "file1.md");
  const file2Path = path.join(tempDir, "file2.md");
  const file3Path = path.join(tempDir, "file3.md");

  await fs.writeFile(file1Path, "[link](./target.md)", "utf8");
  await fs.writeFile(file2Path, "[link](./target.md)", "utf8");
  await fs.writeFile(file3Path, "[link](./target.md)", "utf8");

  console.log("Created files:");
  console.log("- file1.md: [link](./target.md)");
  console.log("- file2.md: [link](./target.md)");
  console.log("- file3.md: [link](./target.md)");

  // Update all files with different path mappings
  const fileUpdates = [
    {
      filePath: file1Path,
      pathMap: new Map([["./target.md", "../target.md"]]),
    },
    {
      filePath: file2Path,
      pathMap: new Map([["./target.md", "../../target.md"]]),
    },
    {
      filePath: file3Path,
      pathMap: new Map([["./target.md", "../../../target.md"]]),
    },
  ];

  const results = await updateMultipleFiles(fileUpdates);

  console.log("\nUpdate results:");
  for (const result of results) {
    const fileName = path.basename(result.filePath);
    console.log(`- ${fileName}: updated=${result.updated}, changes=${result.changesCount}`);
  }

  console.log("\nUpdated contents:");
  for (const result of results) {
    const fileName = path.basename(result.filePath);
    const content = await fs.readFile(result.filePath, "utf8");
    console.log(`- ${fileName}: ${content}`);
  }

  // Clean up
  await fs.rm(tempDir, { recursive: true, force: true });
  console.log("\nCleaned up temporary directory");
}

await updateMultipleFilesExample();
console.log();

// ============================================================================
// Example 4: Validate file before update
// ============================================================================

console.log("Example 4: Validate file before update");
console.log("=".repeat(60));

async function validateFileExample() {
  // Create a temporary file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-example-"));
  const mdFilePath = path.join(tempDir, "test.md");
  const txtFilePath = path.join(tempDir, "test.txt");

  await fs.writeFile(mdFilePath, "# Test", "utf8");
  await fs.writeFile(txtFilePath, "test", "utf8");

  // Validate Markdown file
  const mdValidation = await validateFileForUpdate(mdFilePath);
  console.log("Markdown file validation:");
  console.log("- Valid:", mdValidation.valid);
  console.log("- Reason:", mdValidation.reason || "N/A");

  // Validate text file (should fail)
  const txtValidation = await validateFileForUpdate(txtFilePath);
  console.log("\nText file validation:");
  console.log("- Valid:", txtValidation.valid);
  console.log("- Reason:", txtValidation.reason || "N/A");

  // Validate non-existent file (should fail)
  const nonExistentValidation = await validateFileForUpdate("/nonexistent/file.md");
  console.log("\nNon-existent file validation:");
  console.log("- Valid:", nonExistentValidation.valid);
  console.log("- Reason:", nonExistentValidation.reason || "N/A");

  // Clean up
  await fs.rm(tempDir, { recursive: true, force: true });
  console.log("\nCleaned up temporary directory");
}

await validateFileExample();
console.log();

// ============================================================================
// Example 5: Real-world migration scenario
// ============================================================================

console.log("Example 5: Real-world migration scenario");
console.log("=".repeat(60));

async function realWorldExample() {
  // Simulate a file being moved from plan/oauth2.md to docs/oauth2/overview.md
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-example-"));

  // Create the file at the new location
  const newFilePath = path.join(tempDir, "docs", "oauth2", "overview.md");
  await fs.mkdir(path.dirname(newFilePath), { recursive: true });

  const fileContent = `
# OAuth2 Implementation

## Overview

This document describes the OAuth2 implementation.

## Related Documentation

- [Architecture Overview](../../architecture/overview.md)
- [Security Guide](../../security/oauth2.md)
- [API Reference](../../api/oauth2.md)
- [Examples](../../examples/oauth2-flow.md)

## External Links

- [OAuth2 Spec](https://oauth.net/2/)
- [RFC 6749](https://tools.ietf.org/html/rfc6749)

## See Also

[security]: ../../security/oauth2.md
[examples]: ../../examples/oauth2-flow.md

Check the [security guide][security] and [examples][examples].
`;

  await fs.writeFile(newFilePath, fileContent, "utf8");

  console.log("Simulating file move: plan/oauth2.md -> docs/oauth2/overview.md");
  console.log("Original content:");
  console.log(fileContent);

  // These links were correct when the file was at plan/oauth2.md
  // Now that it's at docs/oauth2/overview.md, they need to be updated
  // The old file was at: plan/oauth2.md
  // The new file is at: docs/oauth2/overview.md
  // So links need to go up one more level

  const migrationPathMap = new Map([
    ["../../architecture/overview.md", "../../../architecture/overview.md"],
    ["../../security/oauth2.md", "../../../security/oauth2.md"],
    ["../../api/oauth2.md", "../../../api/oauth2.md"],
    ["../../examples/oauth2-flow.md", "../../../examples/oauth2-flow.md"],
  ]);

  const result = await updateFileLinks(newFilePath, migrationPathMap);

  console.log("\nUpdate result:");
  console.log("- Updated:", result.updated);
  console.log("- Changes count:", result.changesCount);

  const updatedFileContent = await fs.readFile(newFilePath, "utf8");
  console.log("\nUpdated content:");
  console.log(updatedFileContent);

  // Clean up
  await fs.rm(tempDir, { recursive: true, force: true });
  console.log("\nCleaned up temporary directory");
}

await realWorldExample();
console.log();

console.log("All examples completed successfully!");
