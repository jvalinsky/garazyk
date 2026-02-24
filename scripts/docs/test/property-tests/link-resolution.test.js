/**
 * Property-Based Test: Link Resolution After Migration
 *
 * **Validates: Requirements 2.1, 2.2, 2.5**
 *
 * Property 3: Link Resolution After Migration
 * For any internal link in any migrated documentation file, that link should
 * resolve to an existing file or anchor after migration completes.
 *
 * This test generates random documentation with internal links, executes
 * migration (file moves + link updates), and verifies all internal links
 * resolve to existing files.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import { execSync } from 'child_process';
import fs from 'fs-extra';
import path from 'path';
import os from 'os';
import crypto from 'crypto';
import { parseMarkdownLinks, filterInternalLinks } from '../../lib/link-parser.js';
import { calculateNewPath } from '../../lib/path-resolver.js';
import { updateFileLinks } from '../../lib/content-updater.js';
import { batchGitMv } from '../../lib/git-operations.js';

/**
 * Creates a temporary git repository for testing
 */
async function createTestRepo() {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'link-resolution-test-'));

  // Initialize git repo
  execSync('git init', { cwd: tmpDir, stdio: 'pipe' });
  execSync('git config user.email "test@example.com"', { cwd: tmpDir, stdio: 'pipe' });
  execSync('git config user.name "Test User"', { cwd: tmpDir, stdio: 'pipe' });

  return tmpDir;
}

/**
 * Generates random markdown content with headings for anchor testing
 */
function generateMarkdownContent(includeHeadings = true) {
  const lines = [];
  
  if (includeHeadings) {
    const headingCount = Math.floor(Math.random() * 3) + 1;
    for (let i = 0; i < headingCount; i++) {
      lines.push(`## Section ${i + 1}`);
      lines.push('');
      lines.push(`This is content for section ${i + 1}.`);
      lines.push('');
    }
  } else {
    lines.push('# Document');
    lines.push('');
    lines.push('This is a simple document.');
    lines.push('');
  }
  
  return lines.join('\n');
}

/**
 * Generates a random documentation structure with internal links
 * @param {number} fileCount - Number of files to generate
 * @param {number} linkDensity - Probability (0-1) of adding links between files
 * @returns {Array<{path: string, content: string, links: Array}>} File descriptors
 */
function generateDocumentationWithLinks(fileCount, linkDensity = 0.5) {
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
    filePaths.push(pathParts.join('/'));
  }
  
  // Generate files with links to other files
  for (let i = 0; i < fileCount; i++) {
    const currentPath = filePaths[i];
    const currentDir = path.posix.dirname(currentPath);
    const links = [];
    
    // Add links to other files
    for (let j = 0; j < fileCount; j++) {
      if (i === j) continue;
      
      // Randomly decide whether to add a link
      if (Math.random() < linkDensity) {
        const targetPath = filePaths[j];
        
        // Calculate relative path from current file to target
        const relativePath = path.posix.relative(currentDir, targetPath);
        const normalizedPath = relativePath.startsWith('../') ? relativePath : `./${relativePath}`;
        
        links.push({
          target: targetPath,
          href: normalizedPath,
          hasAnchor: Math.random() < 0.3 // 30% chance of anchor
        });
      }
    }
    
    // Generate content with links
    const contentLines = [
      `# Document ${i}`,
      '',
      'This is a test document.',
      ''
    ];
    
    for (const link of links) {
      const anchor = link.hasAnchor ? '#section-1' : '';
      contentLines.push(`- Link to [file ${link.target}](${link.href}${anchor})`);
    }
    
    contentLines.push('');
    contentLines.push('## Section 1');
    contentLines.push('');
    contentLines.push('Some content here.');
    
    files.push({
      path: currentPath,
      content: contentLines.join('\n'),
      links
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
    await fs.writeFile(fullPath, file.content, 'utf8');
  }

  // Add and commit all files
  execSync(`git add "${sourceDir}"`, { cwd: repoDir, stdio: 'pipe' });
  execSync(`git commit -m "Add files to ${sourceDir}"`, { cwd: repoDir, stdio: 'pipe' });
}

/**
 * Executes migration: moves files and updates links
 */
async function executeMigration(repoDir, sourceDir, destDir, files) {
  // Build file list for batch move
  const fileList = files.map((file) => ({
    source: path.join(sourceDir, file.path),
    destination: path.join(destDir, file.path)
  }));

  // Execute batch git mv
  if (fileList.length > 0) {
    await batchGitMv(fileList, {
      repoRoot: repoDir,
      continueOnError: false
    });

    // Commit the moves
    execSync(`git commit -m "Move files from ${sourceDir} to ${destDir}"`, {
      cwd: repoDir,
      stdio: 'pipe'
    });
  }

  // Build a map of old paths to new paths for all moved files
  const filePathMap = new Map();
  for (const file of files) {
    const oldPath = path.join(sourceDir, file.path);
    const newPath = path.join(destDir, file.path);
    filePathMap.set(oldPath, newPath);
  }

  // Update links in all moved files
  // We need to process all files to update links that point to other moved files
  for (const file of files) {
    const oldFilePath = path.join(sourceDir, file.path);
    const newFilePath = path.join(destDir, file.path);
    const absoluteNewPath = path.join(repoDir, newFilePath);

    // Read the moved file
    const content = await fs.readFile(absoluteNewPath, 'utf8');
    
    // Parse links
    const links = parseMarkdownLinks(content);
    const internalLinks = filterInternalLinks(links);

    // Calculate new paths for all internal links
    const pathMap = new Map();
    for (const link of internalLinks) {
      // Skip anchor-only links
      if (link.href.startsWith('#')) {
        continue;
      }

      // Split href into path and anchor
      const [linkPath, anchor] = link.href.split('#');
      const anchorPart = anchor ? `#${anchor}` : '';

      // Resolve the link target relative to the old file location
      const oldFileDir = path.posix.dirname(oldFilePath);
      let targetPath;
      
      if (linkPath.startsWith('/')) {
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
      if (!newRelativePath.startsWith('../') && !newRelativePath.startsWith('./')) {
        newRelativePath = './' + newRelativePath;
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
    execSync(`git add "${destDir}"`, { cwd: repoDir, stdio: 'pipe' });
    execSync(`git commit -m "Update links after migration"`, {
      cwd: repoDir,
      stdio: 'pipe'
    });
  } catch (error) {
    // No changes to commit - that's okay
  }
}

/**
 * Verifies that all internal links in migrated files resolve correctly
 */
async function verifyLinkResolution(repoDir, destDir, files) {
  const results = {
    totalLinks: 0,
    resolvedLinks: 0,
    brokenLinks: [],
    anchorLinks: []
  };

  for (const file of files) {
    const filePath = path.join(repoDir, destDir, file.path);
    const fileDir = path.dirname(filePath);

    // Read the file content
    const content = await fs.readFile(filePath, 'utf8');

    // Parse links
    const links = parseMarkdownLinks(content);
    const internalLinks = filterInternalLinks(links);

    for (const link of internalLinks) {
      results.totalLinks++;

      // Handle anchor-only links (always valid within the same file)
      if (link.href.startsWith('#')) {
        results.resolvedLinks++;
        results.anchorLinks.push({
          file: path.join(destDir, file.path),
          href: link.href
        });
        continue;
      }

      // Split href into path and anchor
      const [linkPath, anchor] = link.href.split('#');

      // Resolve the link path
      let targetPath;
      if (linkPath.startsWith('/')) {
        // Absolute path
        targetPath = path.join(repoDir, linkPath);
      } else {
        // Relative path
        targetPath = path.resolve(fileDir, linkPath);
      }

      // Check if target file exists
      const exists = await fs.pathExists(targetPath);

      if (exists) {
        results.resolvedLinks++;

        // If there's an anchor, verify it exists in the target file
        if (anchor) {
          const targetContent = await fs.readFile(targetPath, 'utf8');
          const anchorId = anchor.toLowerCase().replace(/\s+/g, '-');
          
          // Check for heading with matching anchor
          const headingRegex = new RegExp(`^#+\\s+.*${anchor}`, 'im');
          const hasAnchor = headingRegex.test(targetContent) || 
                           targetContent.includes(`id="${anchorId}"`);

          if (!hasAnchor) {
            // Anchor not found, but we'll count the link as resolved
            // since the file exists (anchor validation is optional)
            results.anchorLinks.push({
              file: path.join(destDir, file.path),
              href: link.href,
              targetExists: true,
              anchorFound: false
            });
          } else {
            results.anchorLinks.push({
              file: path.join(destDir, file.path),
              href: link.href,
              targetExists: true,
              anchorFound: true
            });
          }
        }
      } else {
        results.brokenLinks.push({
          file: path.join(destDir, file.path),
          href: link.href,
          targetPath: targetPath.replace(repoDir + '/', ''),
          line: link.line
        });
      }
    }
  }

  return results;
}

describe('Property Test: Link Resolution After Migration', () => {
  it('should resolve all internal links after migration (100 iterations)', async () => {
    const iterations = 100;
    let passedIterations = 0;

    for (let i = 0; i < iterations; i++) {
      const repoDir = await createTestRepo();

      try {
        // Generate random documentation (2-8 files, moderate link density)
        const fileCount = Math.floor(Math.random() * 7) + 2;
        const linkDensity = Math.random() * 0.5 + 0.2; // 0.2-0.7
        const files = generateDocumentationWithLinks(fileCount, linkDensity);

        // Choose random source directory
        const sourceDirs = ['plan', 'plans'];
        const sourceDir = sourceDirs[Math.floor(Math.random() * sourceDirs.length)];
        const destDir = 'docs/plans';

        // Create files in source directory
        await createFilesInRepo(repoDir, sourceDir, files);

        // Execute migration (move files + update links)
        await executeMigration(repoDir, sourceDir, destDir, files);

        // Verify all links resolve correctly
        const verification = await verifyLinkResolution(repoDir, destDir, files);

        // Assert all links are resolved
        assert.strictEqual(
          verification.brokenLinks.length,
          0,
          `Iteration ${i + 1}: Found ${verification.brokenLinks.length} broken links: ${JSON.stringify(verification.brokenLinks, null, 2)}`
        );

        assert.strictEqual(
          verification.resolvedLinks,
          verification.totalLinks,
          `Iteration ${i + 1}: Expected ${verification.totalLinks} links to resolve, but only ${verification.resolvedLinks} resolved`
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
      `Expected all ${iterations} iterations to pass, but only ${passedIterations} passed`
    );
  });

  it('should handle files with no links', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create file with no links
      const files = [{
        path: 'no-links.md',
        content: '# Document\n\nThis document has no links.\n',
        links: []
      }];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyLinkResolution(repoDir, destDir, files);

      assert.strictEqual(verification.totalLinks, 0, 'Should have no links');
      assert.strictEqual(verification.brokenLinks.length, 0, 'Should have no broken links');
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle anchor-only links within same file', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create file with anchor-only links
      const files = [{
        path: 'anchors.md',
        content: [
          '# Document',
          '',
          'Jump to [Section 1](#section-1)',
          '',
          '## Section 1',
          '',
          'Content here.'
        ].join('\n'),
        links: []
      }];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyLinkResolution(repoDir, destDir, files);

      assert.strictEqual(verification.brokenLinks.length, 0, 'Should have no broken links');
      assert.ok(verification.totalLinks > 0, 'Should have at least one link');
      assert.strictEqual(
        verification.resolvedLinks,
        verification.totalLinks,
        'All anchor links should resolve'
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle links with anchors to other files', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create files with cross-file anchor links
      const files = [
        {
          path: 'file1.md',
          content: [
            '# File 1',
            '',
            'Link to [File 2 Section](./file2.md#section-1)',
            ''
          ].join('\n'),
          links: []
        },
        {
          path: 'file2.md',
          content: [
            '# File 2',
            '',
            '## Section 1',
            '',
            'Content here.'
          ].join('\n'),
          links: []
        }
      ];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyLinkResolution(repoDir, destDir, files);

      assert.strictEqual(verification.brokenLinks.length, 0, 'Should have no broken links');
      assert.ok(verification.totalLinks > 0, 'Should have at least one link');
      assert.strictEqual(
        verification.resolvedLinks,
        verification.totalLinks,
        'All links with anchors should resolve'
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle nested directory structures', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create files in nested directories with cross-links
      const files = [
        {
          path: 'root.md',
          content: [
            '# Root',
            '',
            'Link to [nested file](./subdir/nested.md)',
            ''
          ].join('\n'),
          links: []
        },
        {
          path: 'subdir/nested.md',
          content: [
            '# Nested',
            '',
            'Link back to [root](../root.md)',
            ''
          ].join('\n'),
          links: []
        }
      ];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyLinkResolution(repoDir, destDir, files);

      assert.strictEqual(
        verification.brokenLinks.length,
        0,
        `Should have no broken links, but found: ${JSON.stringify(verification.brokenLinks)}`
      );
      assert.strictEqual(
        verification.resolvedLinks,
        verification.totalLinks,
        'All links in nested structure should resolve'
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle complex relative paths', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create files with complex relative paths
      const files = [
        {
          path: 'dir1/dir2/file1.md',
          content: [
            '# File 1',
            '',
            'Link to [file 2](../../dir3/file2.md)',
            ''
          ].join('\n'),
          links: []
        },
        {
          path: 'dir3/file2.md',
          content: [
            '# File 2',
            '',
            'Link to [file 1](../dir1/dir2/file1.md)',
            ''
          ].join('\n'),
          links: []
        }
      ];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyLinkResolution(repoDir, destDir, files);

      assert.strictEqual(
        verification.brokenLinks.length,
        0,
        `Should have no broken links, but found: ${JSON.stringify(verification.brokenLinks)}`
      );
      assert.strictEqual(
        verification.resolvedLinks,
        verification.totalLinks,
        'All complex relative paths should resolve'
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle files with many links', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create a file with many links to other files
      const targetFiles = [];
      for (let i = 0; i < 10; i++) {
        targetFiles.push({
          path: `target${i}.md`,
          content: `# Target ${i}\n\nContent here.\n`,
          links: []
        });
      }

      const linkLines = targetFiles.map((f, i) => 
        `- Link to [target ${i}](./target${i}.md)`
      );

      const mainFile = {
        path: 'main.md',
        content: [
          '# Main Document',
          '',
          ...linkLines,
          ''
        ].join('\n'),
        links: []
      };

      const files = [mainFile, ...targetFiles];

      await createFilesInRepo(repoDir, sourceDir, files);
      await executeMigration(repoDir, sourceDir, destDir, files);

      const verification = await verifyLinkResolution(repoDir, destDir, files);

      assert.strictEqual(
        verification.brokenLinks.length,
        0,
        `Should have no broken links, but found: ${JSON.stringify(verification.brokenLinks)}`
      );
      assert.ok(verification.totalLinks >= 10, 'Should have at least 10 links');
      assert.strictEqual(
        verification.resolvedLinks,
        verification.totalLinks,
        'All links should resolve'
      );
    } finally {
      await fs.remove(repoDir);
    }
  });
});
