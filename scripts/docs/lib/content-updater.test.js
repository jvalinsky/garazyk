/**
 * Tests for file content updater
 */

import { test } from "node:test";
import assert from "node:assert";
import fs from "fs/promises";
import path from "path";
import os from "os";
import {
  updateFileLinks,
  updateLinksInContent,
  updateMultipleFiles,
  validateFileForUpdate,
} from "./content-updater.js";

// ============================================================================
// updateLinksInContent tests
// ============================================================================

test("updateLinksInContent replaces simple inline link", () => {
  const content = "Check out [this link](./file.md) for more info.";
  const pathMap = new Map([["./file.md", "../file.md"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../file.md"));
  assert.ok(!updated.includes("](./file.md)"));
});

test("updateLinksInContent replaces multiple links", () => {
  const content = `
First [link](./file1.md) here.
Second [link](../file2.md) there.
Third [link](./file3.md) everywhere.
`;
  const pathMap = new Map([
    ["./file1.md", "../../file1.md"],
    ["../file2.md", "../../file2.md"],
    ["./file3.md", "../file3.md"],
  ]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../../file1.md"));
  assert.ok(updated.includes("../../file2.md"));
  assert.ok(updated.includes("../file3.md"));
});

test("updateLinksInContent preserves links not in pathMap", () => {
  const content = `
[link1](./file1.md)
[link2](./file2.md)
[link3](./file3.md)
`;
  const pathMap = new Map([
    ["./file1.md", "../file1.md"],
  ]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../file1.md"));
  assert.ok(updated.includes("./file2.md"));
  assert.ok(updated.includes("./file3.md"));
});

test("updateLinksInContent handles links with anchors", () => {
  const content = "[link](./file.md#section)";
  const pathMap = new Map([["./file.md#section", "../file.md#section"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../file.md#section"));
});

test("updateLinksInContent handles links with titles", () => {
  const content = '[link](./file.md "Title text")';
  const pathMap = new Map([["./file.md", "../file.md"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes('../file.md "Title text"'));
});

test("updateLinksInContent handles autolinks", () => {
  const content = "Visit <./file.md> for more.";
  const pathMap = new Map([["./file.md", "../file.md"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("<../file.md>"));
});

test("updateLinksInContent handles reference definitions", () => {
  const content = `
[link][ref]

[ref]: ./file.md
`;
  const pathMap = new Map([["./file.md", "../file.md"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("[ref]: ../file.md"));
});

test("updateLinksInContent handles reference definitions with titles", () => {
  const content = '[ref]: ./file.md "Title"';
  const pathMap = new Map([["./file.md", "../file.md"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes('[ref]: ../file.md "Title"'));
});

test("updateLinksInContent preserves external links", () => {
  const content = "[external](https://example.com)";
  const pathMap = new Map([["https://example.com", "https://other.com"]]);

  const updated = updateLinksInContent(content, pathMap);

  // External links should be updated if in pathMap
  assert.ok(updated.includes("https://other.com"));
});

test("updateLinksInContent handles empty pathMap", () => {
  const content = "[link](./file.md)";
  const pathMap = new Map();

  const updated = updateLinksInContent(content, pathMap);

  assert.strictEqual(updated, content);
});

test("updateLinksInContent handles empty content", () => {
  const pathMap = new Map([["./file.md", "../file.md"]]);

  assert.strictEqual(updateLinksInContent("", pathMap), "");
  assert.strictEqual(updateLinksInContent(null, pathMap), "");
  assert.strictEqual(updateLinksInContent(undefined, pathMap), "");
});

test("updateLinksInContent handles null pathMap", () => {
  const content = "[link](./file.md)";

  const updated = updateLinksInContent(content, null);

  assert.strictEqual(updated, content);
});

test("updateLinksInContent preserves line breaks", () => {
  const content = `Line 1
Line 2
Line 3`;
  const pathMap = new Map();

  const updated = updateLinksInContent(content, pathMap);

  assert.strictEqual(updated, content);
  assert.strictEqual(updated.split("\n").length, 3);
});

test("updateLinksInContent handles multiple links on same line", () => {
  const content = "[link1](./file1.md) and [link2](./file2.md)";
  const pathMap = new Map([
    ["./file1.md", "../file1.md"],
    ["./file2.md", "../file2.md"],
  ]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../file1.md"));
  assert.ok(updated.includes("../file2.md"));
});

test("updateLinksInContent handles complex document", () => {
  const content = `
# Documentation

See the [installation guide](./guides/install.md) for setup.

## Links

- [API Reference](../api/reference.md)
- [Examples](./examples/basic.md)

[guide]: ./guides/advanced.md

Check the [advanced guide][guide].
`;

  const pathMap = new Map([
    ["./guides/install.md", "../guides/install.md"],
    ["../api/reference.md", "../../api/reference.md"],
    ["./examples/basic.md", "../examples/basic.md"],
    ["./guides/advanced.md", "../guides/advanced.md"],
  ]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../guides/install.md"));
  assert.ok(updated.includes("../../api/reference.md"));
  assert.ok(updated.includes("../examples/basic.md"));
  assert.ok(updated.includes("../guides/advanced.md"));
});

test("updateLinksInContent handles special characters in paths", () => {
  const content = "[link](./file%20with%20spaces.md)";
  const pathMap = new Map([["./file%20with%20spaces.md", "../file%20with%20spaces.md"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../file%20with%20spaces.md"));
});

test("updateLinksInContent handles paths with query parameters", () => {
  const content = "[link](./file.md?param=value)";
  const pathMap = new Map([["./file.md?param=value", "../file.md?param=value"]]);

  const updated = updateLinksInContent(content, pathMap);

  assert.ok(updated.includes("../file.md?param=value"));
});

// ============================================================================
// updateFileLinks tests
// ============================================================================

test("updateFileLinks updates file content", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "[link](./file.md)";
  await fs.writeFile(filePath, content, "utf8");

  const pathMap = new Map([["./file.md", "../file.md"]]);

  try {
    const result = await updateFileLinks(filePath, pathMap);

    assert.strictEqual(result.updated, true);
    assert.ok(result.changesCount > 0);

    const updatedContent = await fs.readFile(filePath, "utf8");
    assert.ok(updatedContent.includes("../file.md"));
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks preserves file permissions", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "[link](./file.md)";
  await fs.writeFile(filePath, content, "utf8");

  // Set specific permissions
  await fs.chmod(filePath, 0o644);
  const statsBefore = await fs.stat(filePath);

  const pathMap = new Map([["./file.md", "../file.md"]]);

  try {
    await updateFileLinks(filePath, pathMap);

    const statsAfter = await fs.stat(filePath);
    assert.strictEqual(statsAfter.mode, statsBefore.mode);
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks preserves timestamps", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "[link](./file.md)";
  await fs.writeFile(filePath, content, "utf8");

  const statsBefore = await fs.stat(filePath);

  // Wait a bit to ensure timestamps would differ
  await new Promise((resolve) => setTimeout(resolve, 10));

  const pathMap = new Map([["./file.md", "../file.md"]]);

  try {
    await updateFileLinks(filePath, pathMap);

    const statsAfter = await fs.stat(filePath);
    assert.strictEqual(statsAfter.atime.getTime(), statsBefore.atime.getTime());
    assert.strictEqual(statsAfter.mtime.getTime(), statsBefore.mtime.getTime());
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks handles UTF-8 encoding", async () => {
  // Create temp file with UTF-8 content
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "# 文档\n\n[链接](./file.md) 中文内容 🎉";
  await fs.writeFile(filePath, content, "utf8");

  const pathMap = new Map([["./file.md", "../file.md"]]);

  try {
    await updateFileLinks(filePath, pathMap);

    const updatedContent = await fs.readFile(filePath, "utf8");
    assert.ok(updatedContent.includes("文档"));
    assert.ok(updatedContent.includes("中文内容"));
    assert.ok(updatedContent.includes("🎉"));
    assert.ok(updatedContent.includes("../file.md"));
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks returns false when no changes", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "[link](./file.md)";
  await fs.writeFile(filePath, content, "utf8");

  const pathMap = new Map([["./other.md", "../other.md"]]);

  try {
    const result = await updateFileLinks(filePath, pathMap);

    assert.strictEqual(result.updated, false);
    assert.strictEqual(result.changesCount, 0);
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks handles empty pathMap", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "[link](./file.md)";
  await fs.writeFile(filePath, content, "utf8");

  const pathMap = new Map();

  try {
    const result = await updateFileLinks(filePath, pathMap);

    assert.strictEqual(result.updated, false);
    assert.strictEqual(result.changesCount, 0);
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks throws on missing file", async () => {
  const filePath = "/nonexistent/file.md";
  const pathMap = new Map([["./file.md", "../file.md"]]);

  await assert.rejects(
    async () => await updateFileLinks(filePath, pathMap),
    /ENOENT/,
  );
});

test("updateFileLinks throws on missing filePath", async () => {
  const pathMap = new Map([["./file.md", "../file.md"]]);

  await assert.rejects(
    async () => await updateFileLinks(null, pathMap),
    /File path is required/,
  );
});

test("updateFileLinks cleans up temp file on error", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "[link](./file.md)";
  await fs.writeFile(filePath, content, "utf8");

  // Make directory read-only to cause write error
  await fs.chmod(tempDir, 0o555);

  const pathMap = new Map([["./file.md", "../file.md"]]);

  try {
    await assert.rejects(
      async () => await updateFileLinks(filePath, pathMap),
    );

    // Restore permissions to check temp files
    await fs.chmod(tempDir, 0o755);

    // Check that no temp files remain
    const files = await fs.readdir(tempDir);
    const tempFiles = files.filter((f) => f.includes(".tmp."));
    assert.strictEqual(tempFiles.length, 0);
  } finally {
    // Restore permissions and clean up
    await fs.chmod(tempDir, 0o755);
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

// ============================================================================
// updateMultipleFiles tests
// ============================================================================

test("updateMultipleFiles updates multiple files", async () => {
  // Create temp directory with multiple files
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));

  const file1 = path.join(tempDir, "file1.md");
  const file2 = path.join(tempDir, "file2.md");

  await fs.writeFile(file1, "[link](./target.md)", "utf8");
  await fs.writeFile(file2, "[link](./target.md)", "utf8");

  const fileUpdates = [
    {
      filePath: file1,
      pathMap: new Map([["./target.md", "../target.md"]]),
    },
    {
      filePath: file2,
      pathMap: new Map([["./target.md", "../../target.md"]]),
    },
  ];

  try {
    const results = await updateMultipleFiles(fileUpdates);

    assert.strictEqual(results.length, 2);
    assert.strictEqual(results[0].updated, true);
    assert.strictEqual(results[1].updated, true);

    const content1 = await fs.readFile(file1, "utf8");
    const content2 = await fs.readFile(file2, "utf8");

    assert.ok(content1.includes("../target.md"));
    assert.ok(content2.includes("../../target.md"));
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateMultipleFiles handles errors gracefully", async () => {
  const fileUpdates = [
    {
      filePath: "/nonexistent/file.md",
      pathMap: new Map([["./file.md", "../file.md"]]),
    },
  ];

  const results = await updateMultipleFiles(fileUpdates);

  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].updated, false);
  assert.ok(results[0].error);
});

test("updateMultipleFiles handles empty array", async () => {
  const results = await updateMultipleFiles([]);

  assert.strictEqual(results.length, 0);
});

test("updateMultipleFiles throws on invalid input", async () => {
  await assert.rejects(
    async () => await updateMultipleFiles(null),
    /must be an array/,
  );
});

// ============================================================================
// validateFileForUpdate tests
// ============================================================================

test("validateFileForUpdate accepts valid Markdown file", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  await fs.writeFile(filePath, "# Test", "utf8");

  try {
    const result = await validateFileForUpdate(filePath);

    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.reason, undefined);
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("validateFileForUpdate rejects non-existent file", async () => {
  const result = await validateFileForUpdate("/nonexistent/file.md");

  assert.strictEqual(result.valid, false);
  assert.ok(result.reason);
});

test("validateFileForUpdate rejects directory", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));

  try {
    const result = await validateFileForUpdate(tempDir);

    assert.strictEqual(result.valid, false);
    assert.strictEqual(result.reason, "Path is not a file");
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("validateFileForUpdate rejects non-Markdown file", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.txt");

  await fs.writeFile(filePath, "test", "utf8");

  try {
    const result = await validateFileForUpdate(filePath);

    assert.strictEqual(result.valid, false);
    assert.strictEqual(result.reason, "File is not a Markdown file");
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("validateFileForUpdate rejects read-only file", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  await fs.writeFile(filePath, "# Test", "utf8");
  await fs.chmod(filePath, 0o444);

  try {
    const result = await validateFileForUpdate(filePath);

    assert.strictEqual(result.valid, false);
    assert.strictEqual(result.reason, "File is not writable");
  } finally {
    // Restore permissions and clean up
    await fs.chmod(filePath, 0o644);
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

// ============================================================================
// Edge cases and integration tests
// ============================================================================

test("updateFileLinks handles large file", async () => {
  // Create temp file with many links
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  // Generate content with 100 links
  const lines = [];
  for (let i = 0; i < 100; i++) {
    lines.push(`[link${i}](./file${i}.md)`);
  }
  const content = lines.join("\n");

  await fs.writeFile(filePath, content, "utf8");

  // Create pathMap for all links
  const pathMap = new Map();
  for (let i = 0; i < 100; i++) {
    pathMap.set(`./file${i}.md`, `../file${i}.md`);
  }

  try {
    const result = await updateFileLinks(filePath, pathMap);

    assert.strictEqual(result.updated, true);
    assert.ok(result.changesCount > 0);

    const updatedContent = await fs.readFile(filePath, "utf8");

    // Verify all links were updated
    for (let i = 0; i < 100; i++) {
      assert.ok(updatedContent.includes(`../file${i}.md`));
    }
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks handles file with no links", async () => {
  // Create temp file
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = "# Documentation\n\nThis is plain text with no links.";
  await fs.writeFile(filePath, content, "utf8");

  const pathMap = new Map([["./file.md", "../file.md"]]);

  try {
    const result = await updateFileLinks(filePath, pathMap);

    assert.strictEqual(result.updated, false);
    assert.strictEqual(result.changesCount, 0);
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});

test("updateFileLinks preserves content structure", async () => {
  // Create temp file with complex structure
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "content-updater-test-"));
  const filePath = path.join(tempDir, "test.md");

  const content = `# Title

## Section 1

Some text with [link](./file.md).

\`\`\`javascript
// Code block
const x = 1;
\`\`\`

## Section 2

More text.

- List item 1
- List item 2
`;

  await fs.writeFile(filePath, content, "utf8");

  const pathMap = new Map([["./file.md", "../file.md"]]);

  try {
    await updateFileLinks(filePath, pathMap);

    const updatedContent = await fs.readFile(filePath, "utf8");

    // Verify structure is preserved
    assert.ok(updatedContent.includes("# Title"));
    assert.ok(updatedContent.includes("## Section 1"));
    assert.ok(updatedContent.includes("## Section 2"));
    assert.ok(updatedContent.includes("```javascript"));
    assert.ok(updatedContent.includes("const x = 1;"));
    assert.ok(updatedContent.includes("- List item 1"));
    assert.ok(updatedContent.includes("../file.md"));
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
});
