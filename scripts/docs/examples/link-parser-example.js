/**
 * Example usage of the Markdown link parser
 *
 * This example demonstrates how to use the link parser to extract
 * and analyze links from Markdown files.
 */

import {
  filterExternalLinks,
  filterInternalLinks,
  groupLinksByType,
  isInternalLink,
  parseMarkdownLinks,
} from "../lib/link-parser.js";
import fs from "fs-extra";

// Example 1: Parse links from a string
console.log("=== Example 1: Parse links from a string ===\n");

const markdownContent = `
# Documentation

See the [installation guide](./guides/install.md) for setup.

Visit https://example.com for more information.

Jump to [configuration](#configuration) section.

[api]: /docs/api.md
Check the [API docs][api] for details.
`;

const links = parseMarkdownLinks(markdownContent);

console.log(`Found ${links.length} links:\n`);
links.forEach((link) => {
  console.log(`  [${link.type}] "${link.text}" -> ${link.href}`);
  console.log(`    Location: line ${link.line}, column ${link.column}`);
});

// Example 2: Filter internal vs external links
console.log("\n=== Example 2: Filter internal vs external links ===\n");

const internal = filterInternalLinks(links);
const external = filterExternalLinks(links);

console.log(`Internal links (${internal.length}):`);
internal.forEach((link) => {
  console.log(`  - ${link.href}`);
});

console.log(`\nExternal links (${external.length}):`);
external.forEach((link) => {
  console.log(`  - ${link.href}`);
});

// Example 3: Group links by type
console.log("\n=== Example 3: Group links by type ===\n");

const grouped = groupLinksByType(links);

Object.entries(grouped).forEach(([type, typeLinks]) => {
  if (typeLinks.length > 0) {
    console.log(`${type} (${typeLinks.length}):`);
    typeLinks.forEach((link) => {
      console.log(`  - ${link.href}`);
    });
  }
});

// Example 4: Parse links from a file
console.log("\n=== Example 4: Parse links from a file ===\n");

async function analyzeMarkdownFile(filePath) {
  try {
    const content = await fs.readFile(filePath, "utf8");
    const links = parseMarkdownLinks(content);

    console.log(`Analyzing: ${filePath}`);
    console.log(`Total links: ${links.length}`);

    const grouped = groupLinksByType(links);
    console.log(`  Relative: ${grouped.relative.length}`);
    console.log(`  Absolute: ${grouped.absolute.length}`);
    console.log(`  Anchor: ${grouped.anchor.length}`);
    console.log(`  External: ${grouped.external.length}`);
    console.log(`  Reference: ${grouped.reference.length}`);

    // Find broken internal links (simplified check)
    const brokenLinks = [];
    for (const link of filterInternalLinks(links)) {
      if (link.type === "relative" || link.type === "absolute") {
        // In a real implementation, you would resolve the path and check if file exists
        // This is just a placeholder
        console.log(`  Would check: ${link.href}`);
      }
    }

    return links;
  } catch (error) {
    console.error(`Error reading file: ${error.message}`);
    return [];
  }
}

// Example usage (uncomment to use with a real file):
// await analyzeMarkdownFile('README.md');

// Example 5: Update links during migration
console.log("\n=== Example 5: Update links during migration ===\n");

function updateLinksForMigration(content, oldPath, newPath) {
  const links = parseMarkdownLinks(content);

  console.log(`Migrating file from ${oldPath} to ${newPath}`);
  console.log(`Found ${links.length} links to potentially update`);

  // In a real implementation, you would:
  // 1. Calculate new relative paths based on the file move
  // 2. Update each link in the content
  // 3. Return the updated content

  const internalLinks = filterInternalLinks(links);
  console.log(`  ${internalLinks.length} internal links need path updates`);

  return content; // Placeholder
}

const sampleContent = "[link](./other.md)";
updateLinksForMigration(sampleContent, "docs/old/file.md", "docs/new/file.md");

console.log("\n=== Examples complete ===\n");
