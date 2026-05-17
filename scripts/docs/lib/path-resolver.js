/**
 * Path Resolution Logic
 *
 * Calculates new relative paths when files are moved during documentation consolidation.
 * Handles different link formats and preserves anchors, query parameters, and fragments.
 */

import path from "path";

/**
 * Normalizes a path by resolving . and .. segments
 * @param {string} p - Path to normalize
 * @returns {string} Normalized path
 */
function normalizePath(p) {
  // Convert backslashes to forward slashes
  p = p.replace(/\\/g, "/");

  // Remove leading ./
  if (p.startsWith("./")) {
    p = p.substring(2);
  }

  return path.posix.normalize(p);
}

/**
 * Splits a link href into path and fragment components
 * @param {string} href - Link href (may include #anchor or ?query)
 * @returns {{path: string, fragment: string}} Path and fragment parts
 */
export function splitHref(href) {
  if (!href || typeof href !== "string") {
    return { path: "", fragment: "" };
  }

  // Find the first # or ? to split path from fragment
  const hashIndex = href.indexOf("#");
  const queryIndex = href.indexOf("?");

  let splitIndex = -1;
  if (hashIndex !== -1 && queryIndex !== -1) {
    splitIndex = Math.min(hashIndex, queryIndex);
  } else if (hashIndex !== -1) {
    splitIndex = hashIndex;
  } else if (queryIndex !== -1) {
    splitIndex = queryIndex;
  }

  if (splitIndex === -1) {
    return { path: href, fragment: "" };
  }

  return {
    path: href.substring(0, splitIndex),
    fragment: href.substring(splitIndex),
  };
}

/**
 * Calculates the new relative path for a link when a file is moved
 *
 * @param {string} oldFilePath - Original file path (e.g., "plan/oauth2.md")
 * @param {string} newFilePath - New file path (e.g., "docs/oauth2/overview.md")
 * @param {string} linkHref - Original link href from the file (e.g., "../README.md#setup")
 * @returns {string} New link href with updated path
 *
 * @example
 * // File moves from plan/oauth2.md to docs/oauth2/overview.md
 * // Link to ../README.md becomes ../../README.md
 * calculateNewPath('plan/oauth2.md', 'docs/oauth2/overview.md', '../README.md')
 * // => '../../README.md'
 *
 * @example
 * // Preserves anchors
 * calculateNewPath('plan/oauth2.md', 'docs/oauth2/overview.md', '../README.md#setup')
 * // => '../../README.md#setup'
 *
 * @example
 * // Handles absolute paths (unchanged)
 * calculateNewPath('plan/oauth2.md', 'docs/oauth2/overview.md', '/docs/api.md')
 * // => '/docs/api.md'
 *
 * @example
 * // Handles external URLs (unchanged)
 * calculateNewPath('plan/oauth2.md', 'docs/oauth2/overview.md', 'https://example.com')
 * // => 'https://example.com'
 *
 * @example
 * // Handles anchor-only links (unchanged)
 * calculateNewPath('plan/oauth2.md', 'docs/oauth2/overview.md', '#section')
 * // => '#section'
 */
export function calculateNewPath(oldFilePath, newFilePath, linkHref) {
  if (!oldFilePath || !newFilePath || !linkHref) {
    return linkHref || "";
  }

  // External URLs - return unchanged
  if (/^[a-z][a-z0-9+.-]*:/i.test(linkHref)) {
    return linkHref;
  }

  // Anchor-only links - return unchanged
  if (linkHref.startsWith("#")) {
    return linkHref;
  }

  // Absolute paths - return unchanged
  if (linkHref.startsWith("/")) {
    return linkHref;
  }

  // Split href into path and fragment (anchor/query)
  const { path: linkPath, fragment } = splitHref(linkHref);

  // If no path component (e.g., "?query" or just fragment), return unchanged
  if (!linkPath) {
    return linkHref;
  }

  // Normalize paths
  const oldDir = path.posix.dirname(normalizePath(oldFilePath));
  const newDir = path.posix.dirname(normalizePath(newFilePath));

  // Resolve the link target relative to the old file location
  // Join the old directory with the link path to get the absolute target
  const targetPath = path.posix.join(oldDir, linkPath);
  const normalizedTarget = normalizePath(targetPath);

  // Calculate the new relative path from the new file location to the target
  let newRelativePath = path.posix.relative(newDir, normalizedTarget);

  // If the relative path doesn't start with ../, add ./
  if (!newRelativePath.startsWith("../") && !newRelativePath.startsWith("./")) {
    newRelativePath = "./" + newRelativePath;
  }

  // Combine with fragment
  return newRelativePath + fragment;
}

/**
 * Checks if a link href needs path resolution
 * @param {string} href - Link href
 * @returns {boolean} True if the link needs path resolution
 */
export function needsPathResolution(href) {
  if (!href || typeof href !== "string") {
    return false;
  }

  // External URLs don't need resolution
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) {
    return false;
  }

  // Anchor-only links don't need resolution
  if (href.startsWith("#")) {
    return false;
  }

  // Absolute paths don't need resolution
  if (href.startsWith("/")) {
    return false;
  }

  // Query-only or fragment-only without path don't need resolution
  const { path: linkPath } = splitHref(href);
  if (!linkPath) {
    return false;
  }

  // Relative paths need resolution
  return true;
}

/**
 * Batch calculates new paths for multiple links in a file
 * @param {string} oldFilePath - Original file path
 * @param {string} newFilePath - New file path
 * @param {Array<{href: string}>} links - Array of link objects with href property
 * @returns {Map<string, string>} Map of old href to new href
 */
export function calculateNewPaths(oldFilePath, newFilePath, links) {
  const pathMap = new Map();

  for (const link of links) {
    if (!link.href) continue;

    const oldHref = link.href;
    const newHref = calculateNewPath(oldFilePath, newFilePath, oldHref);

    if (oldHref !== newHref) {
      pathMap.set(oldHref, newHref);
    }
  }

  return pathMap;
}

/**
 * Validates that a calculated path is correct
 * @param {string} newFilePath - New file path
 * @param {string} newHref - New calculated href
 * @param {string} expectedTargetPath - Expected target path
 * @returns {boolean} True if the path resolves correctly
 */
export function validateResolvedPath(newFilePath, newHref, expectedTargetPath) {
  if (!newFilePath || !newHref || !expectedTargetPath) {
    return false;
  }

  // External URLs and anchors are always valid
  if (/^[a-z][a-z0-9+.-]*:/i.test(newHref) || newHref.startsWith("#")) {
    return true;
  }

  // Absolute paths - just check they match
  if (newHref.startsWith("/")) {
    const { path: hrefPath } = splitHref(newHref);
    const { path: expectedPath } = splitHref(expectedTargetPath);
    return hrefPath === expectedPath;
  }

  // Relative paths - resolve and compare
  const { path: hrefPath } = splitHref(newHref);
  const { path: expectedPath } = splitHref(expectedTargetPath);

  const newDir = path.posix.dirname(normalizePath(newFilePath));
  const resolvedPath = normalizePath(path.posix.join(newDir, hrefPath));
  const expectedResolved = normalizePath(expectedPath);

  return resolvedPath === expectedResolved;
}
