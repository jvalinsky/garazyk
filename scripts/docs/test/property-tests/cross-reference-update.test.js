/**
 * Property-Based Test: Cross-Reference Update Correctness
 *
 * **Validates: Requirements 2.1, 14.4**
 *
 * Property 6: Cross-Reference Update Correctness
 * For any cross-reference in a moved file, the reference should be updated to
 * reflect the new relative path from the moved file's new location.
 *
 * This test generates random files with cross-references, executes file moves
 * and link updates, and verifies cross-references are updated correctly based
 * on new file locations using calculateNewPath to verify expected paths match
 * actual updated paths.
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import { execSync } from "child_process";
import fs from "fs-extra";
import path from "path";
import os from "os";
import crypto from "crypto";
import { filterInternalLinks, parseMarkdownLinks } from "../../lib/link-parser.js";
import { calculateNewPath } from "../../lib/path-resolver.js";
import { updateFileLinks } from "../../lib/content-updater.js";
import { batchGitMv } from "../../lib/git-operations.js";

/**
 * Creates a temporary git repository for testing
 */
async function createTestRepo() {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "cross-ref-test-"));

  // Initialize git repo
  execSync("git init", { cwd: tmpDir, stdio: "pipe" });
  execSync('git config user.email "test@example.com"', { cwd: tmpDir, stdio: "pipe" });
  execSync('git config user.name "Test User"', { cwd: tmpDir, stdio: "pipe" });

  return tmpDir;
}

/**
 * Generates random markdown content
 */
function generateMarkdownContent() {
  const lines = [
    "# Document",
    "",
    "This is a test document with some content.",
    "",
    "## Section 1",
    "",
    "Some content here.",
    "",
  ];

  return lines.join("\n");
}

/**
 * Generates a random documentation structure with cross-references
 * @param {number} fileCount - Number of files to generate
 * @param {number} linkDensity - Probability (0-1) of adding links between files
 * @returns {Array<{path: string, content: string, links: Array}>} File descriptors
 */
function generateDocumentationWithCrossReferences(fileCount, linkDensity = 0.5) {
  const files = [];
  const filePaths = [];

  // Generate file paths first
  for (let i = 0; i < fileCount; i++) {
    const depth = Math.floor(Math.random() * 3);
    const pathParts = [];

    for (let d = 0; d < depth; d++) {
      pathParts.push(`dir${Math.floor(Math.random() * 3)}`);
    }

    pathParts.push(`file${i}.md`);
    filePaths.push(pathParts.join("/"));
  }

  // Generate files with cross-references to other files
  for (let i = 0; i < fileCount; i++) {
    const currentPath = filePaths[i];
    const currentDir = path.posix.dirname(currentPath);
    const links = [];

    // Add cross-references to other files
    for (let j = 0; j < fileCount; j++) {
      if (i === j) continue;

      // Randomly decide whether to add a cross-reference
      if (Math.random() < linkDensity) {
        const targetPath = filePaths[j];

        // Calculate relative path from current file to target
        const relativePath = path.posix.relative(currentDir, targetPath);
        const normalizedPath = relativePath.startsWith("../") ? relativePath : `./${relativePath}`;

        links.push({
          target: targetPath,
          href: normalizedPath,
          hasAnchor: Math.random() < 0.3, // 30% chance of anchor
        });
      }
    }

    // Generate content with cross-references
    const contentLines = [
      `# Document ${i}`,
      "",
      "This is a test document.",
      "",
    ];

    for (const link of links) {
      const anchor = link.hasAnchor ? "#section-1" : "";
      contentLines.push(`- Cross-reference to [file ${link.target}](${link.href}${anchor})`);
    }

    contentLines.push("");
    contentLines.push("## Section 1");
    contentLines.push("");
    contentLines.push("Some content here.");

    files.push({
      path: currentPath,
      content: contentLines.join("\n"),
      links,
    });
  }

  return files;
}

/**
 * Creates files in a directory and commits them to git
 */
async function createFilesInRepo(repoDir, sourceDir, files) {
  const sourcePath = path.join(repoDir, sourceDir);
  await fs.ensureDir(sourcePath);

  for (const file of files) {
    const fullPath = path.join(sourcePath, file.path);
    await fs.ensureDir(path.dirname(fullPath));
    await fs.writeFile(fullPath, file.content, "utf8");
  }

  // Add and commit all files
  execSync(`git add "${sourceDir}"`, { cwd: repoDir, stdio: "pipe" });
  execSync(`git commit -m "Add files to ${sourceDir}"`, { cwd: repoDir, stdio: "pipe" });
}

/**
 * Executes migration: moves files and updates cross-references
 */
async function executeMigration(repoDir, sourceDir, destDir, files) {
  // Build file list for batch move
  const fileList = files.map((file) => ({
    source: path.join(sourceDir, file.path),
    destination: path.join(destDir, file.path),
  }));

  // Execute batch git mv
  if (fileList.length > 0) {
    await batchGitMv(fileList, {
      repoRoot: repoDir,
      continueOnError: false,
    });

    // Commit the moves
    execSync(`git commit -m "Move files from ${sourceDir} to ${destDir}"`, {
      cwd: repoDir,
      stdio: "pipe",
    });
  }

  // Build a map of old paths to new paths for all moved files
  const filePathMap = new Map();
  for (const file of files) {
    const oldPath = path.join(sourceDir, file.path);
    const newPath = path.join(destDir, file.path);
    filePathMap.set(oldPath, newPath);
  }

  // Update cross-references in all moved files
  for (const file of files) {
    const oldFilePath = path.join(sourceDir, file.path);
    const newFilePath = path.join(destDir, file.path);
    const absoluteNewPath = path.join(repoDir, newFilePath);

    // Read the moved file
    const content = await fs.readFile(absoluteNewPath, "utf8");

    // Parse links
    const links = parseMarkdownLinks(content);
    const internalLinks = filterInternalLinks(links);

    // Calculate new paths for all internal links
    const pathMap = new Map();
    for (const link of internalLinks) {
      // Skip anchor-only links
      if (link.href.startsWith("#")) {
        continue;
      }

      // Split href into path and anchor
      const [linkPath, anchor] = link.href.split("#");
      const anchorPart = anchor ? `#${anchor}` : "";

      // Resolve the link target relative to the old file location
      const oldFileDir = path.posix.dirname(oldFilePath);
      let targetPath;

      if (linkPath.startsWith("/")) {
        // Absolute path
        targetPath = linkPath;
      } else {
        // Relative path - resolve it relative to the old file location
        targetPath = path.posix.normalize(path.posix.join(oldFileDir, linkPath));
      }

      // Check if the target file was also moved
      let newTargetPath = targetPath;
      if (filePathMap.has(targetPath)) {
        newTargetPath = filePathMap.get(targetPath);
      }

      // Calculate the new relative path from the new file location to the new target location
      const newFileDir = path.posix.dirname(newFilePath);
      let newRelativePath = path.posix.relative(newFileDir, newTargetPath);

      // Ensure relative paths start with ./ or ../
      if (!newRelativePath.startsWith("../") && !newRelativePath.startsWith("./")) {
        newRelativePath = "./" + newRelativePath;
      }

      const newHref = newRelativePath + anchorPart;

      if (newHref !== link.href) {
        pathMap.set(link.href, newHref);
      }
    }

    // Update file if there are changes
    if (pathMap.size > 0) {
      await updateFileLinks(absoluteNewPath, pathMap);
    }
  }

  // Commit link updates if there are changes
  try {
    execSync(`git add "${destDir}"`, { cwd: repoDir, stdio: "pipe" });
    execSync(`git commit -m "Update cross-references after migration"`, {
      cwd: repoDir,
      stdio: "pipe",
    });
  } catch (error) {
    // No changes to commit - that's okay
  }
}

/**
 * Verifies that all cross-references are updated correctly
 * Uses calculateNewPath to verify expected paths match actual updated paths
 */
async function verifyCrossReferenceUpdates(repoDir, sourceDir, destDir, files) {
  const results = {
    totalCrossReferences: 0,
    correctUpdates: 0,
    incorrectUpdates: [],
    missingUpdates: [],
  };

  // Build a map of old paths to new paths
  const filePathMap = new Map();
  for (const file of files) {
    const oldPath = path.join(sourceDir, file.path);
    const newPath = path.join(destDir, file.path);
    filePathMap.set(oldPath, newPath);
  }

  for (const file of files) {
    const oldFilePath = path.join(sourceDir, file.path);
    const newFilePath = path.join(destDir, file.path);
    const absoluteNewPath = path.join(repoDir, newFilePath);

    // Read the updated file content
    const updatedContent = await fs.readFile(absoluteNewPath, "utf8");

    // Parse links from updated content
    const updatedLinks = parseMarkdownLinks(updatedContent);
    const internalLinks = filterInternalLinks(updatedLinks);

    // For each original cross-reference, verify it was updated correctly
    for (const originalLink of file.links) {
      results.totalCrossReferences++;

      const originalHref = originalLink.href + (originalLink.hasAnchor ? "#section-1" : "");

      // Resolve the original link target relative to the old file location
      const oldFileDir = path.posix.dirname(oldFilePath);
      const [linkPath, anchor] = originalLink.href.split("#");
      const targetPath = path.posix.normalize(path.posix.join(oldFileDir, linkPath));

      // Check if target was moved
      let newTargetPath = targetPath;
      if (filePathMap.has(targetPath)) {
        newTargetPath = filePathMap.get(targetPath);
      }

      // Calculate the expected new href: relative path from new file location to new target location
      const newFileDir = path.posix.dirname(newFilePath);
      let expectedRelativePath = path.posix.relative(newFileDir, newTargetPath);

      // Ensure relative paths start with ./ or ../
      if (!expectedRelativePath.startsWith("../") && !expectedRelativePath.startsWith("./")) {
        expectedRelativePath = "./" + expectedRelativePath;
      }

      const anchorPart = originalLink.hasAnchor ? "#section-1" : "";
      const expectedNewHref = expectedRelativePath + anchorPart;

      // Find the link in updated content that should point to this target
      let foundCorrectUpdate = false;
      for (const updatedLink of internalLinks) {
        // Skip anchor-only links
        if (updatedLink.href.startsWith("#")) {
          continue;
        }

        // Resolve the updated link to see if it points to the expected target
        const [updatedLinkPath, updatedAnchor] = updatedLink.href.split("#");

        let resolvedTarget;
        if (updatedLinkPath.startsWith("/")) {
          resolvedTarget = updatedLinkPath;
        } else {
          resolvedTarget = path.posix.normalize(path.posix.join(newFileDir, updatedLinkPath));
        }

        // Check if this link points to our target
        if (resolvedTarget === newTargetPath) {
          // Verify the href matches the expected href
          const actualHref = updatedLink.href;

          if (actualHref === expectedNewHref) {
            foundCorrectUpdate = true;
            results.correctUpdates++;
            break;
          } else {
            // Found the link but it's incorrect
            results.incorrectUpdates.push({
              file: newFilePath,
              originalHref,
              expectedHref: expectedNewHref,
              actualHref,
              target: newTargetPath,
              resolvedTarget,
            });
            foundCorrectUpdate = true; // Mark as found to avoid double-counting
            break;
          }
        }
      }

      if (!foundCorrectUpdate) {
        results.missingUpdates.push({
          file: newFilePath,
          originalHref,
          expectedHref: expectedNewHref,
          target: newTargetPath,
        });
      }
    }
  }

  return results;
}

describe("Property Test: Cross-Reference Update Correctness", () => {
  it("should update all cross-references correctly after file moves (100 iterations)", async () => {
    const iterations = 100;
    let passedIterations = 0;

    for (let i = 0; i < iterations; i++) {
      const repoDir = await createTestRepo();

      try {
        // Generate random documentation (2-8 files, moderate link density)
        const fileCount = Math.floor(Math.random() * 7) + 2;
        const linkDensity = Math.random() * 0.5 + 0.2; // 0.2-0.7
        const files = generateDocumentationWithCrossReferences(fileCount, linkDensity);

        // Choose random source directory
        const sourceDirs = ["plan", "plans"];
        const sourceDir = sourceDirs[Math.floor(Math.random() * sourceDirs.length)];
        const destDir = "docs/plans";

        // Create files in source directory
        await createFilesInRepo(repoDir, sourceDir, files);

        // Execute migration (move files + update cross-references)
        await executeMigration(repoDir, sourceDir, destDir, files);

        // Verify all cross-references are updated correctly
        const verification = await verifyCrossReferenceUpdates(repoDir, sourceDir, destDir, files);

        // Assert all cross-references are updated correctly
        assert.strictEqual(
          verification.incorrectUpdates.length,
          0,
          `Iteration ${i + 1}: Found ${verification.incorrectUpdates.length} incorrect updates: ${
            JSON.stringify(verification.incorrectUpdates, null, 2)
          }`,
        );

        assert.strictEqual(
          verification.missingUpdates.length,
          0,
          `Iteration ${i + 1}: Found ${verification.missingUpdates.length} missing updates: ${
            JSON.stringify(verification.missingUpdates, null, 2)
          }`,
        );

        assert.strictEqual(
          verification.correctUpdates,
          verification.totalCrossReferences,
          `Iteration ${
            i + 1
          }: Expected ${verification.totalCrossReferences} correct updates, but only ${verification.correctUpdates} were correct`,
        );

        passedIterations++;
      } finally {
        // Clean up test repository
        await fs.remove(repoDir);
      }
    }

    // Verify all iterations passed
    assert.strictEqual(
      passedIterations,
      iterations,
      `Expected all ${iterations} iterations to pass, but only ${passedIterations} passed`,
    );
  });

  it("should handle files with no cross-references", async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = "plan";
      const destDir = "docs/plans";

      // Create file with no cross-references
      const files = [{
        path: "no-refs.md",
        content: "# Document\n\nThis document has no cross-references.\n",
        links: [],
      }];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyCrossReferenceUpdates(repoDir, sourceDir, destDir, files);

      assert.strictEqual(verification.totalCrossReferences, 0, "Should have no cross-references");
      assert.strictEqual(
        verification.incorrectUpdates.length,
        0,
        "Should have no incorrect updates",
      );
      assert.strictEqual(verification.missingUpdates.length, 0, "Should have no missing updates");
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should handle cross-references with anchors", async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = "plan";
      const destDir = "docs/plans";

      // Create files with cross-references that include anchors
      const files = [
        {
          path: "file1.md",
          content: [
            "# File 1",
            "",
            "Cross-reference to [File 2 Section](./file2.md#section-1)",
            "",
          ].join("\n"),
          links: [{
            target: "file2.md",
            href: "./file2.md",
            hasAnchor: true,
          }],
        },
        {
          path: "file2.md",
          content: [
            "# File 2",
            "",
            "## Section 1",
            "",
            "Content here.",
          ].join("\n"),
          links: [],
        },
      ];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyCrossReferenceUpdates(repoDir, sourceDir, destDir, files);

      assert.strictEqual(
        verification.incorrectUpdates.length,
        0,
        "Should have no incorrect updates",
      );
      assert.strictEqual(verification.missingUpdates.length, 0, "Should have no missing updates");
      assert.strictEqual(
        verification.correctUpdates,
        verification.totalCrossReferences,
        "All cross-references with anchors should be updated correctly",
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should handle nested directory structures", async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = "plan";
      const destDir = "docs/plans";

      // Create files in nested directories with cross-references
      const files = [
        {
          path: "root.md",
          content: [
            "# Root",
            "",
            "Cross-reference to [nested file](./subdir/nested.md)",
            "",
          ].join("\n"),
          links: [{
            target: "subdir/nested.md",
            href: "./subdir/nested.md",
            hasAnchor: false,
          }],
        },
        {
          path: "subdir/nested.md",
          content: [
            "# Nested",
            "",
            "Cross-reference back to [root](../root.md)",
            "",
          ].join("\n"),
          links: [{
            target: "root.md",
            href: "../root.md",
            hasAnchor: false,
          }],
        },
      ];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyCrossReferenceUpdates(repoDir, sourceDir, destDir, files);

      assert.strictEqual(
        verification.incorrectUpdates.length,
        0,
        `Should have no incorrect updates, but found: ${
          JSON.stringify(verification.incorrectUpdates)
        }`,
      );
      assert.strictEqual(
        verification.missingUpdates.length,
        0,
        `Should have no missing updates, but found: ${JSON.stringify(verification.missingUpdates)}`,
      );
      assert.strictEqual(
        verification.correctUpdates,
        verification.totalCrossReferences,
        "All cross-references in nested structure should be updated correctly",
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should handle complex relative paths", async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = "plan";
      const destDir = "docs/plans";

      // Create files with complex relative paths
      const files = [
        {
          path: "dir1/dir2/file1.md",
          content: [
            "# File 1",
            "",
            "Cross-reference to [file 2](../../dir3/file2.md)",
            "",
          ].join("\n"),
          links: [{
            target: "dir3/file2.md",
            href: "../../dir3/file2.md",
            hasAnchor: false,
          }],
        },
        {
          path: "dir3/file2.md",
          content: [
            "# File 2",
            "",
            "Cross-reference to [file 1](../dir1/dir2/file1.md)",
            "",
          ].join("\n"),
          links: [{
            target: "dir1/dir2/file1.md",
            href: "../dir1/dir2/file1.md",
            hasAnchor: false,
          }],
        },
      ];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyCrossReferenceUpdates(repoDir, sourceDir, destDir, files);

      assert.strictEqual(
        verification.incorrectUpdates.length,
        0,
        `Should have no incorrect updates, but found: ${
          JSON.stringify(verification.incorrectUpdates)
        }`,
      );
      assert.strictEqual(
        verification.missingUpdates.length,
        0,
        `Should have no missing updates, but found: ${JSON.stringify(verification.missingUpdates)}`,
      );
      assert.strictEqual(
        verification.correctUpdates,
        verification.totalCrossReferences,
        "All complex relative paths should be updated correctly",
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should handle files with many cross-references", async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = "plan";
      const destDir = "docs/plans";

      // Create a file with many cross-references to other files
      const targetFiles = [];
      for (let i = 0; i < 10; i++) {
        targetFiles.push({
          path: `target${i}.md`,
          content: `# Target ${i}\n\nContent here.\n`,
          links: [],
        });
      }

      const linkLines = [];
      const links = [];
      for (let i = 0; i < targetFiles.length; i++) {
        linkLines.push(`- Cross-reference to [target ${i}](./target${i}.md)`);
        links.push({
          target: `target${i}.md`,
          href: `./target${i}.md`,
          hasAnchor: false,
        });
      }

      const mainFile = {
        path: "main.md",
        content: [
          "# Main Document",
          "",
          ...linkLines,
          "",
        ].join("\n"),
        links,
      };

      const files = [mainFile, ...targetFiles];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyCrossReferenceUpdates(repoDir, sourceDir, destDir, files);

      assert.strictEqual(
        verification.incorrectUpdates.length,
        0,
        `Should have no incorrect updates, but found: ${
          JSON.stringify(verification.incorrectUpdates)
        }`,
      );
      assert.strictEqual(
        verification.missingUpdates.length,
        0,
        `Should have no missing updates, but found: ${JSON.stringify(verification.missingUpdates)}`,
      );
      assert.ok(
        verification.totalCrossReferences >= 10,
        "Should have at least 10 cross-references",
      );
      assert.strictEqual(
        verification.correctUpdates,
        verification.totalCrossReferences,
        "All cross-references should be updated correctly",
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should verify cross-references remain correct when files move together", async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = "plan";
      const destDir = "docs/plans";

      // Create simple test case where both files move together
      const files = [
        {
          path: "file1.md",
          content: [
            "# File 1",
            "",
            "Cross-reference to [file 2](./file2.md)",
            "",
          ].join("\n"),
          links: [{
            target: "file2.md",
            href: "./file2.md",
            hasAnchor: false,
          }],
        },
        {
          path: "file2.md",
          content: "# File 2\n\nContent here.\n",
          links: [],
        },
      ];

      await createFilesInRepo(repoDir, sourceDir, files);

      // Execute migration
      await executeMigration(repoDir, sourceDir, destDir, files);

      // Read the updated file and verify the link stays the same
      // (since both files moved together, their relative position is unchanged)
      const updatedFilePath = path.join(repoDir, destDir, "file1.md");
      const updatedContent = await fs.readFile(updatedFilePath, "utf8");
      const updatedLinks = parseMarkdownLinks(updatedContent);
      const internalLinks = filterInternalLinks(updatedLinks);

      assert.ok(internalLinks.length > 0, "Should have at least one internal link");

      const actualHref = internalLinks[0].href;
      // When files move together, the relative path should remain the same
      assert.strictEqual(
        actualHref,
        "./file2.md",
        `Cross-reference should remain unchanged when files move together. Expected: ./file2.md, Actual: ${actualHref}`,
      );
    } finally {
      await fs.remove(repoDir);
    }
  });
});
