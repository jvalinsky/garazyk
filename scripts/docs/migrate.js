#!/usr/bin/env node

/**
 * Documentation Migration Tool
 *
 * Consolidates documentation from multiple source directories into
 * the unified docs/ structure while preserving git history and
 * updating all cross-references.
 *
 * Usage: node migrate.js [config-file]
 */

import { version } from "./index.js";
import path from "path";
import { execSync } from "child_process";
import fs from "fs-extra";
import { loadMigrationConfig } from "./lib/migration-schema.js";
import { discoverFiles } from "./lib/file-discovery.js";
import { batchGitMv } from "./lib/git-operations.js";
import { filterInternalLinks, parseMarkdownLinks } from "./lib/link-parser.js";
import { splitHref } from "./lib/path-resolver.js";
import { updateFileLinks } from "./lib/content-updater.js";
import { generateAndWriteMapping, readMigrationMapping } from "./lib/migration-mapping.js";
import { createMigrationData, generateAndWriteReport } from "./lib/migration-report.js";
import { removeEmptyDirectories } from "./lib/directory-cleanup.js";

console.log(`Documentation Migration Tool v${version}`);

function getRepoRoot(cwd = process.cwd()) {
  try {
    return execSync("git rev-parse --show-toplevel", {
      cwd,
      stdio: "pipe",
      encoding: "utf8",
    }).trim();
  } catch {
    return cwd;
  }
}

function normalizeRepoPath(p) {
  if (!p) return "";
  return p.replace(/\\/g, "/").replace(/^\.\/+/, "");
}

function computeDestinationPath(migration, discoveredRelativePath) {
  const rel = normalizeRepoPath(discoveredRelativePath);
  if (migration.preserveStructure !== false) {
    return path.posix.join(migration.destination, rel);
  }
  return path.posix.join(migration.destination, path.posix.basename(rel));
}

function computeUpdatedHref({
  oldFilePath,
  newFilePath,
  href,
  movedPathMap,
}) {
  if (!href || typeof href !== "string") {
    return href || "";
  }

  // External schemes unchanged
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) {
    return href;
  }

  // Anchor-only links unchanged
  if (href.startsWith("#")) {
    return href;
  }

  const { path: linkPath, fragment } = splitHref(href);

  // Query-only / fragment-only links unchanged
  if (!linkPath) {
    return href;
  }

  const oldFile = normalizeRepoPath(oldFilePath);
  const newFile = normalizeRepoPath(newFilePath);

  // Absolute internal links: keep absolute style; only update if target moved
  if (linkPath.startsWith("/")) {
    const oldTarget = normalizeRepoPath(linkPath.slice(1));
    const newTarget = movedPathMap.get(oldTarget) || oldTarget;
    const newAbsHref = `/${newTarget}${fragment}`;
    return newAbsHref;
  }

  // Relative internal links
  const originalHadDotSlash = linkPath.startsWith("./");
  const oldDir = path.posix.dirname(oldFile);
  const oldTarget = normalizeRepoPath(path.posix.normalize(path.posix.join(oldDir, linkPath)));
  const newTarget = movedPathMap.get(oldTarget) || oldTarget;

  const newDir = path.posix.dirname(newFile);
  let newRel = path.posix.relative(newDir, newTarget);
  if (originalHadDotSlash && !newRel.startsWith("../") && !newRel.startsWith("./")) {
    newRel = `./${newRel}`;
  }

  return `${newRel}${fragment}`;
}

async function updateReferencesAcrossRepo({
  repoRoot,
  movedPathMap,
  reverseMovedPathMap,
  dryRun,
  verbose,
}) {
  const excludePatterns = [
    "**/.git/**",
    "**/node_modules/**",
    "**/build/**",
    "**/tmp/**",
    "**/.DS_Store",
    "**/Thumbs.db",
  ];

  const markdownFiles = await discoverFiles(".", {
    filePatterns: ["**/*.md"],
    excludePatterns,
    repoRoot,
  });

  const linkUpdates = [];

  for (const currentFilePath of markdownFiles) {
    const newFilePath = normalizeRepoPath(currentFilePath);
    const fileMoved = reverseMovedPathMap.has(newFilePath);
    const oldFilePath = reverseMovedPathMap.get(newFilePath) || newFilePath;

    const absPath = path.resolve(repoRoot, newFilePath);
    const content = await fs.readFile(absPath, "utf8");

    const links = parseMarkdownLinks(content);
    const internalLinks = filterInternalLinks(links);

    const pathMap = new Map();

    for (const link of internalLinks) {
      // Only update links in-place for non-moved files when they point at a moved target.
      // For moved files, all relative links may need updating due to directory changes.
      const { path: linkPath } = splitHref(link.href);
      let targetOldPath = null;

      if (linkPath) {
        if (linkPath.startsWith("/")) {
          targetOldPath = normalizeRepoPath(linkPath.slice(1));
        } else if (!/^[a-z][a-z0-9+.-]*:/i.test(linkPath) && !linkPath.startsWith("#")) {
          const oldDir = path.posix.dirname(normalizeRepoPath(oldFilePath));
          targetOldPath = normalizeRepoPath(
            path.posix.normalize(path.posix.join(oldDir, linkPath)),
          );
        }
      }

      const targetMoved = targetOldPath ? movedPathMap.has(targetOldPath) : false;
      if (!fileMoved && !targetMoved) {
        continue;
      }

      const newHref = computeUpdatedHref({
        oldFilePath,
        newFilePath,
        href: link.href,
        movedPathMap,
      });

      if (newHref && newHref !== link.href) {
        if (!pathMap.has(link.href)) {
          pathMap.set(link.href, newHref);
        }
        linkUpdates.push({
          file: newFilePath,
          oldLink: link.href,
          newLink: newHref,
        });
      }
    }

    if (pathMap.size === 0) {
      continue;
    }

    if (verbose) {
      console.log(`Updating links in ${newFilePath} (${pathMap.size} unique hrefs)`);
    }

    if (!dryRun) {
      await updateFileLinks(absPath, pathMap);
    }
  }

  return linkUpdates;
}

async function runMigration(configPath) {
  const repoRoot = getRepoRoot(process.cwd());
  const config = await loadMigrationConfig(configPath);

  const dryRun = config.options?.dryRun === true;
  const verbose = config.options?.verbose === true;
  const continueOnError = config.options?.continueOnError === true;
  const mappingOutputPath = path.resolve(
    repoRoot,
    config.options?.mappingPath || "migration-mapping.json",
  );

  if (config.description) {
    console.log(config.description);
  }
  console.log(`Repo root: ${repoRoot}`);
  console.log(`Config: ${configPath}`);
  console.log(`Dry run: ${dryRun}\n`);

  const allFileList = [];
  const destinationPaths = new Set();

  for (const migration of config.migrations) {
    const discovered = await discoverFiles(migration.source, {
      filePatterns: migration.filePatterns,
      excludePatterns: migration.excludePatterns,
      repoRoot,
    });

    const destNames = new Set();
    const fileList = discovered.map((rel) => {
      const dest = computeDestinationPath(migration, rel);
      if (migration.preserveStructure === false) {
        const base = path.posix.basename(dest);
        if (destNames.has(base)) {
          throw new Error(`Destination collision in ${migration.destination}: ${base}`);
        }
        destNames.add(base);
      }

      return {
        source: normalizeRepoPath(path.posix.join(migration.source, rel)),
        destination: normalizeRepoPath(dest),
      };
    });

    for (const entry of fileList) {
      const key = entry.destination;
      if (destinationPaths.has(key)) {
        throw new Error(`Duplicate destination path across migrations: ${key}`);
      }
      destinationPaths.add(key);
      allFileList.push(entry);
    }
  }

  let skipMoves = false;
  if (allFileList.length === 0) {
    // Resume support: if a previous run wrote a mapping, re-use it to finish
    // reference updates / cleanup / report generation.
    if (await fs.pathExists(mappingOutputPath)) {
      const mapping = await readMigrationMapping(mappingOutputPath);
      if (mapping?.mappings?.length > 0) {
        if (verbose) {
          console.log(
            `No sources found; resuming from mapping: ${
              path.relative(repoRoot, mappingOutputPath)
            }`,
          );
        }
        for (const entry of mapping.mappings) {
          if (!entry?.oldPath || !entry?.newPath) {
            continue;
          }
          allFileList.push({
            source: normalizeRepoPath(entry.oldPath),
            destination: normalizeRepoPath(entry.newPath),
          });
        }
        skipMoves = true;
      }
    }
  }

  if (allFileList.length === 0) {
    console.log("No files to migrate.");
    return {
      repoRoot,
      config,
      operations: { moves: [], linkUpdates: [], errors: [], validation: { passed: true } },
    };
  }

  // Generate mapping before moving (captures metadata at old paths)
  if (config.options?.generateReport !== false) {
    if (verbose) {
      console.log(`Generating mapping: ${path.relative(repoRoot, mappingOutputPath)}`);
    }
    if (!dryRun && !skipMoves) {
      await generateAndWriteMapping(allFileList, mappingOutputPath, { repoRoot });
    }
  }

  // Perform git mv operations
  const moveResults = [];
  const errors = [];

  if (verbose) {
    console.log(`Moving ${allFileList.length} files via git mv...`);
  }

  try {
    if (skipMoves) {
      for (const entry of allFileList) {
        moveResults.push({
          source: entry.source,
          destination: entry.destination,
          error: null,
          resumed: true,
        });
      }
    } else {
      const batch = await batchGitMv(allFileList, {
        repoRoot,
        dryRun,
        verbose,
        continueOnError,
      });

      for (const result of batch.results) {
        moveResults.push({
          source: result.sourcePath,
          destination: result.destPath,
          error: result.success ? null : result.message,
        });
      }
    }
  } catch (error) {
    errors.push({ type: "git", message: error.message, details: error.stderr?.toString?.() });
    throw error;
  }

  // Build moved path maps
  const movedPathMap = new Map();
  const reverseMovedPathMap = new Map();
  for (const entry of allFileList) {
    movedPathMap.set(entry.source, entry.destination);
    reverseMovedPathMap.set(entry.destination, entry.source);
  }

  // Update references
  let linkUpdates = [];
  if (config.migrations.some((m) => m.updateReferences !== false)) {
    if (verbose) {
      console.log("\nUpdating references across repository...");
    }
    linkUpdates = await updateReferencesAcrossRepo({
      repoRoot,
      movedPathMap,
      reverseMovedPathMap,
      dryRun,
      verbose,
    });
  }

  // Remove empty dirs
  for (const migration of config.migrations) {
    if (migration.removeEmptyDirs === false) {
      continue;
    }
    if (verbose) {
      console.log(`\nCleaning empty directories under ${migration.source}...`);
    }
    await removeEmptyDirectories(migration.source, {
      repoRoot,
      dryRun,
      removeRoot: true,
    });
  }

  const operations = {
    moves: moveResults,
    linkUpdates,
    errors,
    validation: { passed: true },
  };

  // Generate report
  if (config.options?.generateReport !== false) {
    const reportOutputPath = path.resolve(
      repoRoot,
      config.options?.reportPath || "migration-report.json",
    );
    if (verbose) {
      console.log(`\nWriting report: ${path.relative(repoRoot, reportOutputPath)}`);
    }
    if (!dryRun) {
      const migrationData = createMigrationData(operations);
      await generateAndWriteReport(migrationData, reportOutputPath, { repoRoot });
    }
  }

  return { repoRoot, config, operations };
}

const configPathArg = process.argv[2] || "configs/plan-consolidation.json";

try {
  await runMigration(configPathArg);
  process.exit(0);
} catch (error) {
  console.error("\nMigration failed.");
  console.error(error?.message || error);
  process.exit(1);
}
