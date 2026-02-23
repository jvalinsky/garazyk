/**
 * File Discovery and Filtering
 *
 * Provides functionality to recursively scan directories and filter files
 * based on glob patterns. Used by the migration tool to identify which
 * files need to be moved.
 */

import fs from 'fs-extra';
import path from 'path';

/**
 * Simple glob pattern matcher
 * Supports: *, **, ?, [abc], {a,b,c}
 *
 * @param {string} filePath - File path to test
 * @param {string} pattern - Glob pattern
 * @param {Object} options - Matching options
 * @returns {boolean} True if path matches pattern
 */
function matchGlob(filePath, pattern, options = {}) {
  const { dot = true, nocase = false } = options;

  // Normalize paths to use forward slashes
  const normalizedPath = filePath.split(path.sep).join('/');
  const normalizedPattern = pattern.split(path.sep).join('/');

  // Handle case sensitivity
  const testPath = nocase ? normalizedPath.toLowerCase() : normalizedPath;
  const testPattern = nocase ? normalizedPattern.toLowerCase() : normalizedPattern;

  // Don't match dotfiles unless dot option is true or pattern explicitly includes them
  if (!dot && !testPattern.includes('/.') && testPath.includes('/.')) {
    return false;
  }

  // Convert glob pattern to regex
  // Use a unique placeholder that won't appear in paths
  const GLOBSTAR_PLACEHOLDER = '\uFFFF';
  const STAR_PLACEHOLDER = '\uFFFE';
  const QUESTION_PLACEHOLDER = '\uFFFD';

  let regexPattern = testPattern
    // Replace glob wildcards with placeholders
    .replace(/\*\*/g, GLOBSTAR_PLACEHOLDER)
    .replace(/\*/g, STAR_PLACEHOLDER)
    .replace(/\?/g, QUESTION_PLACEHOLDER)
    // Escape special regex characters
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    // Replace placeholders with regex patterns
    // ** should match zero or more path segments (including empty)
    .replace(new RegExp(GLOBSTAR_PLACEHOLDER, 'g'), '(?:.*?)')
    .replace(new RegExp(STAR_PLACEHOLDER, 'g'), '[^/]*')
    .replace(new RegExp(QUESTION_PLACEHOLDER, 'g'), '[^/]');

  // Handle leading ** to match from start
  if (regexPattern.startsWith('^(?:.*?)/')) {
    regexPattern = '^(?:(?:.*?)/)?'  + regexPattern.slice('^(?:.*?)/'.length);
  }
  
  // Handle trailing ** to match to end
  if (regexPattern.endsWith('/(?:.*?)$')) {
    regexPattern = regexPattern.slice(0, -'/(?:.*?)$'.length) + '/(?:.*)?$';
  }

  // Anchor the pattern
  regexPattern = `^${regexPattern}$`;

  const regex = new RegExp(regexPattern);
  return regex.test(testPath);
}

/**
 * Recursively scans a directory and returns all file paths
 *
 * @param {string} dirPath - Directory to scan (absolute path)
 * @param {string} basePath - Base path for calculating relative paths
 * @returns {Promise<Array<string>>} Array of relative file paths
 */
async function scanDirectory(dirPath, basePath) {
  const files = [];

  try {
    const entries = await fs.readdir(dirPath, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = path.join(dirPath, entry.name);
      const relativePath = path.relative(basePath, fullPath);

      if (entry.isDirectory()) {
        // Recursively scan subdirectories
        const subFiles = await scanDirectory(fullPath, basePath);
        files.push(...subFiles);
      } else if (entry.isFile()) {
        // Add file with forward slashes for consistent glob matching
        files.push(relativePath.split(path.sep).join('/'));
      }
      // Skip symbolic links and other special files
    }
  } catch (error) {
    // If directory doesn't exist or can't be read, return empty array
    if (error.code !== 'ENOENT' && error.code !== 'EACCES') {
      throw error;
    }
  }

  return files;
}

/**
 * Checks if a file path matches any of the given glob patterns
 *
 * @param {string} filePath - File path to check (with forward slashes)
 * @param {Array<string>} patterns - Array of glob patterns
 * @returns {boolean} True if file matches any pattern
 */
function matchesAnyPattern(filePath, patterns) {
  if (!patterns || patterns.length === 0) {
    return false;
  }

  return patterns.some((pattern) => {
    return matchGlob(filePath, pattern, { dot: true, nocase: false });
  });
}

/**
 * Discovers files in a directory based on include and exclude patterns
 *
 * @param {string} sourceDir - Source directory to scan (relative to repo root)
 * @param {Object} options - Discovery options
 * @param {Array<string>} options.filePatterns - Glob patterns for files to include
 * @param {Array<string>} options.excludePatterns - Glob patterns for files to exclude
 * @param {string} options.repoRoot - Repository root directory (absolute path)
 * @returns {Promise<Array<string>>} Array of discovered file paths (relative to sourceDir)
 */
export async function discoverFiles(sourceDir, options = {}) {
  const {
    filePatterns = ['**/*'],
    excludePatterns = [
      '**/.git/**',
      '**/node_modules/**',
      '**/.DS_Store',
      '**/Thumbs.db'
    ],
    repoRoot = process.cwd()
  } = options;

  // Convert source directory to absolute path
  const absoluteSourceDir = path.resolve(repoRoot, sourceDir);

  // Check if source directory exists
  if (!await fs.pathExists(absoluteSourceDir)) {
    return [];
  }

  // Scan directory recursively
  const allFiles = await scanDirectory(absoluteSourceDir, absoluteSourceDir);

  // Filter files based on patterns
  const filteredFiles = allFiles.filter((filePath) => {
    // Check if file matches any exclude pattern
    if (matchesAnyPattern(filePath, excludePatterns)) {
      return false;
    }

    // Check if file matches any include pattern
    if (filePatterns.length === 0 || filePatterns.includes('**/*')) {
      // No specific patterns, include all non-excluded files
      return true;
    }

    return matchesAnyPattern(filePath, filePatterns);
  });

  return filteredFiles;
}

/**
 * Discovers files for multiple migrations
 *
 * @param {Array<Object>} migrations - Array of migration configurations
 * @param {string} repoRoot - Repository root directory (absolute path)
 * @returns {Promise<Map<string, Array<string>>>} Map of source directory to file list
 */
export async function discoverFilesForMigrations(migrations, repoRoot = process.cwd()) {
  const fileMap = new Map();

  for (const migration of migrations) {
    const files = await discoverFiles(migration.source, {
      filePatterns: migration.filePatterns,
      excludePatterns: migration.excludePatterns,
      repoRoot
    });

    fileMap.set(migration.source, files);
  }

  return fileMap;
}

/**
 * Checks if a directory is empty (contains no files after filtering)
 *
 * @param {string} dirPath - Directory to check (relative to repo root)
 * @param {Object} options - Check options
 * @param {Array<string>} options.excludePatterns - Patterns to exclude when checking
 * @param {string} options.repoRoot - Repository root directory (absolute path)
 * @returns {Promise<boolean>} True if directory is empty or doesn't exist
 */
export async function isDirectoryEmpty(dirPath, options = {}) {
  const {
    excludePatterns = ['**/.git/**'],
    repoRoot = process.cwd()
  } = options;

  const files = await discoverFiles(dirPath, {
    filePatterns: ['**/*'],
    excludePatterns,
    repoRoot
  });

  return files.length === 0;
}

/**
 * Finds all empty directories within a directory tree
 *
 * @param {string} rootDir - Root directory to search (relative to repo root)
 * @param {Object} options - Search options
 * @param {Array<string>} options.excludePatterns - Patterns to exclude when checking
 * @param {string} options.repoRoot - Repository root directory (absolute path)
 * @returns {Promise<Array<string>>} Array of empty directory paths (relative to repo root)
 */
export async function findEmptyDirectories(rootDir, options = {}) {
  const {
    excludePatterns = ['**/.git/**'],
    repoRoot = process.cwd()
  } = options;

  const absoluteRootDir = path.resolve(repoRoot, rootDir);
  const emptyDirs = [];

  // Check if root directory exists
  if (!await fs.pathExists(absoluteRootDir)) {
    return [];
  }

  /**
   * Recursively checks directories
   * @param {string} dirPath - Absolute directory path
   * @returns {Promise<boolean>} True if directory is empty
   */
  async function checkDirectory(dirPath) {
    const entries = await fs.readdir(dirPath, { withFileTypes: true });
    let hasFiles = false;
    let hasNonEmptySubdirs = false;

    for (const entry of entries) {
      const fullPath = path.join(dirPath, entry.name);
      const relativePath = path.relative(repoRoot, fullPath);

      // Check if this path should be excluded
      const shouldExclude = matchesAnyPattern(
        relativePath.split(path.sep).join('/'),
        excludePatterns
      );

      if (shouldExclude) {
        continue;
      }

      if (entry.isFile()) {
        hasFiles = true;
      } else if (entry.isDirectory()) {
        const subdirEmpty = await checkDirectory(fullPath);
        if (!subdirEmpty) {
          hasNonEmptySubdirs = true;
        }
      }
    }

    const isEmpty = !hasFiles && !hasNonEmptySubdirs;

    if (isEmpty && dirPath !== absoluteRootDir) {
      emptyDirs.push(path.relative(repoRoot, dirPath));
    }

    return isEmpty;
  }

  await checkDirectory(absoluteRootDir);

  // Sort by depth (deepest first) for safe removal
  emptyDirs.sort((a, b) => {
    const depthA = a.split(path.sep).length;
    const depthB = b.split(path.sep).length;
    return depthB - depthA;
  });

  return emptyDirs;
}
