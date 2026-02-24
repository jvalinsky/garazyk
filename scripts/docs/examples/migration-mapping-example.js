/**
 * Migration Mapping Generator Example
 *
 * Demonstrates how to use the migration mapping generator to create
 * an audit trail of file moves during documentation consolidation.
 */

import {
  generateMappingEntry,
  generateMigrationMapping,
  generateAndWriteMapping,
  readMigrationMapping,
  lookupNewPath,
  lookupOldPath
} from '../lib/migration-mapping.js';

/**
 * Example 1: Generate a single mapping entry
 */
async function example1() {
  console.log('Example 1: Generate a single mapping entry\n');

  const entry = await generateMappingEntry(
    'plan/oauth2-implementation.md',
    'docs/plans/oauth2-implementation.md',
    process.cwd()
  );

  console.log('Mapping entry:');
  console.log(JSON.stringify(entry, null, 2));
  console.log();
}

/**
 * Example 2: Generate mapping for multiple files
 */
async function example2() {
  console.log('Example 2: Generate mapping for multiple files\n');

  const fileList = [
    { source: 'plan/oauth2-implementation.md', destination: 'docs/plans/oauth2-implementation.md' },
    { source: 'plan/repository-sync.md', destination: 'docs/plans/repository-sync.md' },
    { source: 'plans/deployment-guide.md', destination: 'docs/guides/deployment.md' }
  ];

  const mapping = await generateMigrationMapping(fileList, process.cwd());

  console.log('Migration mapping summary:');
  console.log(`  Total files: ${mapping.totalFiles}`);
  console.log(`  Successful: ${mapping.successfulMappings}`);
  console.log(`  Failed: ${mapping.failedMappings}`);
  console.log(`  Generated at: ${mapping.generatedAt}`);
  console.log();

  console.log('First mapping:');
  console.log(JSON.stringify(mapping.mappings[0], null, 2));
  console.log();
}

/**
 * Example 3: Generate and write mapping to file
 */
async function example3() {
  console.log('Example 3: Generate and write mapping to file\n');

  const fileList = [
    { source: 'plan/oauth2-implementation.md', destination: 'docs/plans/oauth2-implementation.md' },
    { source: 'plan/repository-sync.md', destination: 'docs/plans/repository-sync.md' }
  ];

  const mapping = await generateAndWriteMapping(
    fileList,
    'migration-mapping.json',
    { repoRoot: process.cwd() }
  );

  console.log('Mapping written to migration-mapping.json');
  console.log(`  Total files: ${mapping.totalFiles}`);
  console.log(`  Successful: ${mapping.successfulMappings}`);
  console.log();
}

/**
 * Example 4: Read mapping and perform lookups
 */
async function example4() {
  console.log('Example 4: Read mapping and perform lookups\n');

  // First, create a mapping file
  const fileList = [
    { source: 'plan/oauth2-implementation.md', destination: 'docs/plans/oauth2-implementation.md' },
    { source: 'plan/repository-sync.md', destination: 'docs/plans/repository-sync.md' },
    { source: 'plans/deployment-guide.md', destination: 'docs/guides/deployment.md' }
  ];

  await generateAndWriteMapping(
    fileList,
    'migration-mapping.json',
    { repoRoot: process.cwd() }
  );

  // Read the mapping back
  const mapping = await readMigrationMapping('migration-mapping.json');

  console.log('Mapping loaded from file');
  console.log();

  // Lookup new path for old path
  const oldPath = 'plan/oauth2-implementation.md';
  const newPath = lookupNewPath(mapping, oldPath);
  console.log(`Old path: ${oldPath}`);
  console.log(`New path: ${newPath}`);
  console.log();

  // Lookup old path for new path
  const newPath2 = 'docs/guides/deployment.md';
  const oldPath2 = lookupOldPath(mapping, newPath2);
  console.log(`New path: ${newPath2}`);
  console.log(`Old path: ${oldPath2}`);
  console.log();
}

/**
 * Example 5: Handle files that don't exist
 */
async function example5() {
  console.log('Example 5: Handle files that don\'t exist\n');

  const fileList = [
    { source: 'existing-file.md', destination: 'docs/existing.md' },
    { source: 'nonexistent-file.md', destination: 'docs/nonexistent.md' }
  ];

  const mapping = await generateMigrationMapping(fileList, process.cwd());

  console.log('Mapping with non-existent files:');
  console.log(`  Total files: ${mapping.totalFiles}`);
  console.log(`  Successful: ${mapping.successfulMappings}`);
  console.log();

  // Show mapping for non-existent file
  const nonexistentMapping = mapping.mappings.find(
    (m) => m.oldPath === 'nonexistent-file.md'
  );

  if (nonexistentMapping) {
    console.log('Mapping for non-existent file:');
    console.log(JSON.stringify(nonexistentMapping, null, 2));
    console.log();
  }
}

/**
 * Example 6: Complete migration workflow
 */
async function example6() {
  console.log('Example 6: Complete migration workflow\n');

  // Define files to migrate
  const fileList = [
    { source: 'plan/oauth2-implementation.md', destination: 'docs/plans/oauth2-implementation.md' },
    { source: 'plan/repository-sync.md', destination: 'docs/plans/repository-sync.md' },
    { source: 'plan/websocket-firehose.md', destination: 'docs/plans/websocket-firehose.md' },
    { source: 'plans/deployment-guide.md', destination: 'docs/guides/deployment.md' },
    { source: 'plans/security-checklist.md', destination: 'docs/guides/security.md' }
  ];

  console.log('Generating migration mapping...');

  // Generate and write mapping
  const mapping = await generateAndWriteMapping(
    fileList,
    'migration-mapping.json',
    { repoRoot: process.cwd() }
  );

  console.log('Migration mapping generated successfully!');
  console.log();
  console.log('Summary:');
  console.log(`  Total files: ${mapping.totalFiles}`);
  console.log(`  Successful mappings: ${mapping.successfulMappings}`);
  console.log(`  Failed mappings: ${mapping.failedMappings}`);
  console.log(`  Generated at: ${mapping.generatedAt}`);
  console.log(`  Output file: migration-mapping.json`);
  console.log();

  // Show statistics
  const totalSize = mapping.mappings.reduce((sum, m) => sum + (m.size || 0), 0);
  const filesWithGitHistory = mapping.mappings.filter((m) => m.gitCommit).length;

  console.log('Statistics:');
  console.log(`  Total size: ${totalSize} bytes`);
  console.log(`  Files with git history: ${filesWithGitHistory}/${mapping.mappings.length}`);
  console.log();

  // Show sample mappings
  console.log('Sample mappings:');
  mapping.mappings.slice(0, 3).forEach((m, i) => {
    console.log(`  ${i + 1}. ${m.oldPath} → ${m.newPath}`);
    console.log(`     Size: ${m.size} bytes, Commit: ${m.gitCommit?.substring(0, 8) || 'none'}`);
  });
  console.log();
}

/**
 * Run all examples
 */
async function runExamples() {
  console.log('='.repeat(70));
  console.log('Migration Mapping Generator Examples');
  console.log('='.repeat(70));
  console.log();

  try {
    // Note: These examples assume certain files exist in the repository
    // Uncomment the examples you want to run

    // await example1();
    // await example2();
    // await example3();
    // await example4();
    // await example5();
    // await example6();

    console.log('Examples completed successfully!');
    console.log();
    console.log('To run these examples:');
    console.log('  1. Uncomment the example functions you want to run');
    console.log('  2. Ensure the source files exist in your repository');
    console.log('  3. Run: node scripts/docs/examples/migration-mapping-example.js');
  } catch (error) {
    console.error('Error running examples:', error.message);
    process.exit(1);
  }
}

// Run examples if this file is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  runExamples();
}

export {
  example1,
  example2,
  example3,
  example4,
  example5,
  example6
};
