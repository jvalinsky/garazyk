/**
 * File Content Updater
 * 
 * Updates Markdown file content by replacing links based on a path mapping.
 * Handles atomic writes, preserves file permissions and timestamps, and ensures UTF-8 encoding.
 */

import fs from 'fs/promises';
import path from 'path';
import { parseMarkdownLinks } from './link-parser.js';
import { needsPathResolution } from './path-resolver.js';

/**
 * Updates links in file content based on a path mapping
 * @param {string} content - Original file content
 * @param {Map<string, string>} pathMap - Map of old href to new href
 * @returns {string} Updated content with replaced links
 */
export function updateLinksInContent(content, pathMap) {
  if (!content || typeof content !== 'string') {
    return content || '';
  }
  
  if (!pathMap || pathMap.size === 0) {
    return content;
  }
  
  let updatedContent = content;
  
  // Process each path mapping
  for (const [oldHref, newHref] of pathMap) {
    if (oldHref === newHref) {
      continue;
    }
    
    // Escape special regex characters
    const escapedOld = escapeRegex(oldHref);
    
    // Pattern for inline links: [text](href) or [text](href "title")
    const inlinePattern = new RegExp(`(\\[[^\\]]+\\]\\()${escapedOld}((?:\\s+"[^"]*")?\\))`, 'g');
    updatedContent = updatedContent.replace(inlinePattern, `$1${newHref}$2`);
    
    // Pattern for autolinks: <href>
    const autolinkPattern = new RegExp(`(<)${escapedOld}(>)`, 'g');
    updatedContent = updatedContent.replace(autolinkPattern, `$1${newHref}$2`);
    
    // Pattern for reference definitions: [id]: href or [id]: href "title"
    // Must be at start of line (possibly with leading whitespace)
    const refDefPattern = new RegExp(`^(\\s*\\[[^\\]]+\\]:\\s*)${escapedOld}((?:\\s+"[^"]*")?\\s*)$`, 'gm');
    updatedContent = updatedContent.replace(refDefPattern, `$1${newHref}$2`);
  }
  
  return updatedContent;
}

/**
 * Escapes special regex characters in a string
 * @param {string} str - String to escape
 * @returns {string} Escaped string
 */
function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Updates links in a file based on a path mapping
 * Reads the file, updates links, and writes back atomically
 * 
 * @param {string} filePath - Path to the file to update
 * @param {Map<string, string>} pathMap - Map of old href to new href
 * @returns {Promise<{updated: boolean, changesCount: number}>} Update result
 * 
 * @example
 * const pathMap = new Map([
 *   ['../README.md', '../../README.md'],
 *   ['./other.md', '../other.md']
 * ]);
 * await updateFileLinks('docs/guide.md', pathMap);
 */
export async function updateFileLinks(filePath, pathMap) {
  if (!filePath) {
    throw new Error('File path is required');
  }
  
  if (!pathMap || pathMap.size === 0) {
    return { updated: false, changesCount: 0 };
  }
  
  // Read file stats to preserve permissions and timestamps
  const stats = await fs.stat(filePath);
  
  // Read file content as UTF-8
  const content = await fs.readFile(filePath, 'utf8');
  
  // Update links in content
  const updatedContent = updateLinksInContent(content, pathMap);
  
  // Check if content actually changed
  if (updatedContent === content) {
    return { updated: false, changesCount: 0 };
  }
  
  // Count the number of changes
  const changesCount = countChanges(content, updatedContent);
  
  // Write atomically: write to temp file, then rename
  const tempPath = `${filePath}.tmp.${Date.now()}`;
  
  try {
    // Write to temp file
    await fs.writeFile(tempPath, updatedContent, 'utf8');
    
    // Preserve file permissions
    await fs.chmod(tempPath, stats.mode);
    
    // Atomic rename
    await fs.rename(tempPath, filePath);
    
    // Preserve timestamps
    await fs.utimes(filePath, stats.atime, stats.mtime);
    
    return { updated: true, changesCount };
  } catch (error) {
    // Clean up temp file on error
    try {
      await fs.unlink(tempPath);
    } catch (unlinkError) {
      // Ignore unlink errors
    }
    throw error;
  }
}

/**
 * Counts the number of differences between two strings
 * @param {string} original - Original content
 * @param {string} updated - Updated content
 * @returns {number} Number of changes
 */
function countChanges(original, updated) {
  if (original === updated) {
    return 0;
  }
  
  // Simple line-based diff count
  const originalLines = original.split('\n');
  const updatedLines = updated.split('\n');
  
  let changes = 0;
  const maxLines = Math.max(originalLines.length, updatedLines.length);
  
  for (let i = 0; i < maxLines; i++) {
    if (originalLines[i] !== updatedLines[i]) {
      changes++;
    }
  }
  
  return changes;
}

/**
 * Updates links in multiple files based on their path mappings
 * @param {Array<{filePath: string, pathMap: Map<string, string>}>} fileUpdates - Array of file update specs
 * @returns {Promise<Array<{filePath: string, updated: boolean, changesCount: number, error?: Error}>>} Update results
 */
export async function updateMultipleFiles(fileUpdates) {
  if (!Array.isArray(fileUpdates)) {
    throw new Error('fileUpdates must be an array');
  }
  
  const results = [];
  
  for (const { filePath, pathMap } of fileUpdates) {
    try {
      const result = await updateFileLinks(filePath, pathMap);
      results.push({
        filePath,
        ...result
      });
    } catch (error) {
      results.push({
        filePath,
        updated: false,
        changesCount: 0,
        error
      });
    }
  }
  
  return results;
}

/**
 * Validates that a file can be updated safely
 * @param {string} filePath - Path to the file
 * @returns {Promise<{valid: boolean, reason?: string}>} Validation result
 */
export async function validateFileForUpdate(filePath) {
  try {
    // Check if file exists
    const stats = await fs.stat(filePath);
    
    // Check if it's a file (not a directory)
    if (!stats.isFile()) {
      return { valid: false, reason: 'Path is not a file' };
    }
    
    // Check if file is readable
    try {
      await fs.access(filePath, fs.constants.R_OK);
    } catch {
      return { valid: false, reason: 'File is not readable' };
    }
    
    // Check if file is writable
    try {
      await fs.access(filePath, fs.constants.W_OK);
    } catch {
      return { valid: false, reason: 'File is not writable' };
    }
    
    // Check if file is a Markdown file
    if (!filePath.endsWith('.md')) {
      return { valid: false, reason: 'File is not a Markdown file' };
    }
    
    return { valid: true };
  } catch (error) {
    return { valid: false, reason: error.message };
  }
}
