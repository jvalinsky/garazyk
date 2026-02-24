#!/usr/bin/env node

/**
 * Git Operations Example
 *
 * Demonstrates how to use the git operations module for documentation migration.
 * This example shows:
 * - Single file moves with git mv
 * - Batch file moves
 * - Dry run mode
 * - Error handling and rollback
 * - History verification
 */

import {
  executeGitMv,
  batchGitMv,
  verifyHistoryPreservation,
  isGitRepository
} from '../lib/git-operations.js';

/**
 * Example 1: Single file move
 */
async function example1_singleFileMove() {
  console.log('\n=== Example 1: Single File Move ===\n');

  try {
    const result = await executeGitMv(
      'old-docs/guide.md',
      'docs/guides/guide.md',
      {
        repoRoot: process.cwd(),
        verbose: true,
        dryRun: false
      }
    );

    if (result.success) {
      console.log('✓', result.message);
    } else {
      console.log('✗', result.message);
    }
  } catch (error) {
    console.error('Error:', error.message);
  }
}

/**
 * Example 2: Batch file move with progress tracking
 */
async function example2_batchFileMove() {
  console.log('\n=== Example 2: Batch File Move ===\n');

  const fileList = [
    { source: 'plan/architecture.md', destination: 'docs/architecture/overview.md' },
    { source: 'plan/deployment.md', destination: 'docs/guides/deployment.md' },
    { source: 'plan/testing.md', destination: 'docs/testing/strategy.md' }
  ];

  try {
    const result = await batchGitMv(fileList, {
      repoRoot: process.cwd(),
      verbose: true,
      continueOnError: false,
      onProgress: (current, total, fileResult) => {
        console.log(`Progress: ${current}/${total} - ${fileResult.message}`);
      }
    });

    console.log('\nSummary:');
    console.log(`  Total: ${result.summary.total}`);
    console.log(`  Success: ${result.summary.success}`);
    console.log(`  Failed: ${result.summary.failed}`);
    console.log(`  Skipped: ${result.summary.skipped}`);

    if (result.errors.length > 0) {
      console.log('\nErrors:');
      result.errors.forEach((error) => {
        console.log(`  - ${error.file.source}: ${error.message}`);
      });
    }
  } catch (error) {
    console.error('Batch operation failed:', error.message);
  }
}

/**
 * Example 3: Dry run mode
 */
async function example3_dryRun() {
  console.log('\n=== Example 3: Dry Run Mode ===\n');

  const fileList = [
    { source: 'plans/feature-a.md', destination: 'docs/plans/feature-a.md' },
    { source: 'plans/feature-b.md', destination: 'docs/plans/feature-b.md' }
  ];

  try {
    const result = await batchGitMv(fileList, {
      repoRoot: process.cwd(),
      dryRun: true,
      verbose: true
    });

    console.log('\nDry run completed successfully');
    console.log('No actual changes were made');
    console.log(`Would have moved ${result.summary.success} files`);
  } catch (error) {
    console.error('Dry run failed:', error.message);
  }
}

/**
 * Example 4: Error handling with continueOnError
 */
async function example4_continueOnError() {
  console.log('\n=== Example 4: Continue On Error ===\n');

  const fileList = [
    { source: 'docs/valid1.md', destination: 'docs/moved1.md' },
    { source: 'docs/nonexistent.md', destination: 'docs/moved2.md' }, // Will fail
    { source: 'docs/valid2.md', destination: 'docs/moved3.md' }
  ];

  try {
    const result = await batchGitMv(fileList, {
      repoRoot: process.cwd(),
      continueOnError: true,
      verbose: true
    });

    console.log('\nBatch completed with errors:');
    console.log(`  Successful: ${result.summary.success}`);
    console.log(`  Failed: ${result.summary.failed}`);

    if (result.errors.length > 0) {
      console.log('\nFailed files:');
      result.errors.forEach((error) => {
        console.log(`  - ${error.file.source}: ${error.message}`);
      });
    }
  } catch (error) {
    console.error('Unexpected error:', error.message);
  }
}

/**
 * Example 5: Verify history preservation
 */
async function example5_verifyHistory() {
  console.log('\n=== Example 5: Verify History Preservation ===\n');

  const filePath = 'docs/guides/deployment.md';

  try {
    const verification = await verifyHistoryPreservation(filePath, {
      repoRoot: process.cwd(),
      minCommits: 1
    });

    if (verification.preserved) {
      console.log('✓ History preserved');
      console.log(`  Commits found: ${verification.commitCount}`);
      console.log('\n  Recent commits:');
      verification.history.slice(0, 5).forEach((commit) => {
        console.log(`    ${commit}`);
      });
    } else {
      console.log('✗ History not preserved');
      console.log(`  ${verification.message}`);
    }
  } catch (error) {
    console.error('Verification failed:', error.message);
  }
}

/**
 * Example 6: Complete migration workflow
 */
async function example6_completeMigration() {
  console.log('\n=== Example 6: Complete Migration Workflow ===\n');

  // Check if we're in a git repository
  if (!isGitRepository()) {
    console.error('Error: Not in a git repository');
    return;
  }

  const fileList = [
    { source: 'plan/overview.md', destination: 'docs/architecture/overview.md' },
    { source: 'plan/api.md', destination: 'docs/guides/api.md' }
  ];

  try {
    // Step 1: Dry run to preview changes
    console.log('Step 1: Dry run...');
    const dryRunResult = await batchGitMv(fileList, {
      dryRun: true,
      verbose: false
    });

    if (!dryRunResult.success) {
      console.error('Dry run failed, aborting migration');
      return;
    }

    console.log(`✓ Dry run successful (${dryRunResult.summary.success} files)`);

    // Step 2: Execute actual migration
    console.log('\nStep 2: Executing migration...');
    const migrationResult = await batchGitMv(fileList, {
      verbose: true,
      continueOnError: false,
      onProgress: (current, total) => {
        console.log(`  Progress: ${current}/${total}`);
      }
    });

    if (!migrationResult.success) {
      console.error('Migration failed');
      return;
    }

    console.log('✓ Migration successful');

    // Step 3: Verify history for moved files
    console.log('\nStep 3: Verifying history preservation...');
    for (const file of fileList) {
      const verification = await verifyHistoryPreservation(file.destination, {
        minCommits: 1
      });

      if (verification.preserved) {
        console.log(`  ✓ ${file.destination}: ${verification.commitCount} commits`);
      } else {
        console.log(`  ✗ ${file.destination}: ${verification.message}`);
      }
    }

    console.log('\n✓ Migration workflow completed successfully');
  } catch (error) {
    console.error('Migration workflow failed:', error.message);
  }
}

// Main execution
async function main() {
  const example = process.argv[2];

  console.log('Git Operations Examples');
  console.log('======================');

  switch (example) {
  case '1':
    await example1_singleFileMove();
    break;
  case '2':
    await example2_batchFileMove();
    break;
  case '3':
    await example3_dryRun();
    break;
  case '4':
    await example4_continueOnError();
    break;
  case '5':
    await example5_verifyHistory();
    break;
  case '6':
    await example6_completeMigration();
    break;
  default:
    console.log('\nUsage: node git-operations-example.js <example-number>');
    console.log('\nAvailable examples:');
    console.log('  1 - Single file move');
    console.log('  2 - Batch file move with progress');
    console.log('  3 - Dry run mode');
    console.log('  4 - Continue on error');
    console.log('  5 - Verify history preservation');
    console.log('  6 - Complete migration workflow');
    console.log('\nNote: These examples use placeholder file paths.');
    console.log('Modify the file paths to match your actual files.');
  }
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
