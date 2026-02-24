/**
 * Path Resolver Example
 * 
 * Demonstrates how to use the path resolver to update links when files move.
 */

import {
  calculateNewPath,
  calculateNewPaths,
  needsPathResolution,
  splitHref,
  validateResolvedPath
} from '../lib/path-resolver.js';

console.log('=== Path Resolver Examples ===\n');

// Example 1: Basic path resolution
console.log('Example 1: File moves to deeper directory');
console.log('------------------------------------------');
const oldPath1 = 'plan/oauth2.md';
const newPath1 = 'docs/oauth2/overview.md';
const link1 = '../README.md';

const newLink1 = calculateNewPath(oldPath1, newPath1, link1);
console.log(`File moves: ${oldPath1} → ${newPath1}`);
console.log(`Link updates: ${link1} → ${newLink1}`);
console.log();

// Example 2: Preserving anchors
console.log('Example 2: Preserving anchors and query parameters');
console.log('---------------------------------------------------');
const link2 = '../README.md#quick-start?version=2';
const newLink2 = calculateNewPath(oldPath1, newPath1, link2);
console.log(`File moves: ${oldPath1} → ${newPath1}`);
console.log(`Link updates: ${link2} → ${newLink2}`);
console.log();

// Example 3: External URLs remain unchanged
console.log('Example 3: External URLs remain unchanged');
console.log('------------------------------------------');
const link3 = 'https://atproto.com/specs/oauth';
const newLink3 = calculateNewPath(oldPath1, newPath1, link3);
console.log(`File moves: ${oldPath1} → ${newPath1}`);
console.log(`Link updates: ${link3} → ${newLink3}`);
console.log(`Needs resolution: ${needsPathResolution(link3)}`);
console.log();

// Example 4: Anchor-only links remain unchanged
console.log('Example 4: Anchor-only links remain unchanged');
console.log('----------------------------------------------');
const link4 = '#introduction';
const newLink4 = calculateNewPath(oldPath1, newPath1, link4);
console.log(`File moves: ${oldPath1} → ${newPath1}`);
console.log(`Link updates: ${link4} → ${newLink4}`);
console.log(`Needs resolution: ${needsPathResolution(link4)}`);
console.log();

// Example 5: Batch processing multiple links
console.log('Example 5: Batch processing multiple links');
console.log('-------------------------------------------');
const links = [
  { href: '../README.md#setup', text: 'Setup Guide' },
  { href: './implementation.md', text: 'Implementation' },
  { href: 'https://example.com', text: 'External' },
  { href: '#section', text: 'Section' },
  { href: '/docs/api.md', text: 'API Docs' }
];

const pathMap = calculateNewPaths(oldPath1, newPath1, links);
console.log(`File moves: ${oldPath1} → ${newPath1}`);
console.log(`Processing ${links.length} links...`);
console.log(`Updated ${pathMap.size} links:\n`);

for (const [oldHref, newHref] of pathMap.entries()) {
  console.log(`  ${oldHref} → ${newHref}`);
}
console.log();

// Example 6: Splitting href into path and fragment
console.log('Example 6: Splitting href components');
console.log('-------------------------------------');
const complexHref = '../docs/guide.md?version=2#installation';
const { path, fragment } = splitHref(complexHref);
console.log(`Original: ${complexHref}`);
console.log(`Path: ${path}`);
console.log(`Fragment: ${fragment}`);
console.log();

// Example 7: Validating resolved paths
console.log('Example 7: Validating resolved paths');
console.log('-------------------------------------');
const newFilePath = 'docs/oauth2/overview.md';
const resolvedHref = '../../README.md';
const expectedTarget = 'README.md';

const isValid = validateResolvedPath(newFilePath, resolvedHref, expectedTarget);
console.log(`New file: ${newFilePath}`);
console.log(`Resolved link: ${resolvedHref}`);
console.log(`Expected target: ${expectedTarget}`);
console.log(`Valid: ${isValid}`);
console.log();

// Example 8: Real-world migration scenario
console.log('Example 8: Real-world migration scenario');
console.log('-----------------------------------------');
console.log('Migrating OAuth2 documentation from plan/ to docs/oauth2/\n');

const migrationScenario = {
  oldFile: 'plan/oauth2-implementation.md',
  newFile: 'docs/oauth2/implementation.md',
  links: [
    { href: '../README.md', text: 'Main README' },
    { href: './oauth2-flows.md', text: 'OAuth2 Flows' },
    { href: '../AGENTS.md#oauth2', text: 'Agent Instructions' },
    { href: 'https://oauth.net/2/', text: 'OAuth 2.0 Spec' },
    { href: '#dpop-implementation', text: 'DPoP Section' }
  ]
};

console.log(`Migrating: ${migrationScenario.oldFile}`);
console.log(`       to: ${migrationScenario.newFile}\n`);

const updates = calculateNewPaths(
  migrationScenario.oldFile,
  migrationScenario.newFile,
  migrationScenario.links
);

console.log('Link updates:');
for (const link of migrationScenario.links) {
  const newHref = updates.get(link.href) || link.href;
  const status = updates.has(link.href) ? '✓ UPDATED' : '  (unchanged)';
  console.log(`  ${status} [${link.text}]`);
  console.log(`           ${link.href} → ${newHref}`);
}
console.log();

// Example 9: Checking which links need resolution
console.log('Example 9: Filtering links that need resolution');
console.log('------------------------------------------------');
const mixedLinks = [
  '../README.md',
  'https://example.com',
  '#section',
  '/absolute/path.md',
  './relative.md',
  'mailto:test@example.com'
];

console.log('Links requiring path resolution:');
for (const href of mixedLinks) {
  const needs = needsPathResolution(href);
  console.log(`  ${needs ? '✓' : '✗'} ${href}`);
}
