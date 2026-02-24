/**
 * Property-Based Test: Migration Report Generation
 *
 * **Validates: Requirements 14.5**
 *
 * Property 27: Migration Report Generation
 * For any completed migration execution, a migration report file should be
 * generated containing statistics and status of all moved files.
 *
 * This test generates random migration execution data, generates reports,
 * and verifies all required information is present and accurate.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'fs-extra';
import path from 'path';
import os from 'os';
import {
  generateMigrationReport,
  writeMigrationReport,
  generateAndWriteReport,
  readMigrationReport,
  createMigrationData
} from '../../lib/migration-report.js';

/**
 * Generates random migration execution data
 *
 * @param {number} fileCount - Number of files to include
 * @param {number} linkCount - Number of link updates to include
 * @param {number} errorCount - Number of errors to include
 * @returns {Object} Migration data object
 */
function generateRandomMigrationData(fileCount, linkCount, errorCount) {
  const movedFiles = [];
  const updatedLinks = [];
  const errors = [];

  // Generate moved files (mix of success and failure)
  for (let i = 0; i < fileCount; i++) {
    const shouldFail = Math.random() < 0.1; // 10% failure rate
    movedFiles.push({
      source: `source/dir${Math.floor(Math.random() * 5)}/file${i}.md`,
      destination: `dest/dir${Math.floor(Math.random() * 5)}/file${i}.md`,
      status: shouldFail ? 'failed' : 'success',
      error: shouldFail ? `Failed to move file${i}.md` : undefined
    });
  }

  // Generate link updates
  for (let i = 0; i < linkCount; i++) {
    const shouldFail = Math.random() < 0.05; // 5% failure rate
    updatedLinks.push({
      file: `dest/file${Math.floor(Math.random() * fileCount)}.md`,
      oldLink: `../old/path${i}.md`,
      newLink: `../new/path${i}.md`,
      status: shouldFail ? 'failed' : 'success',
      error: shouldFail ? `Failed to update link ${i}` : undefined
    });
  }

  // Generate errors
  const errorTypes = ['file_move', 'link_update', 'validation', 'git_operation'];
  for (let i = 0; i < errorCount; i++) {
    errors.push({
      type: errorTypes[Math.floor(Math.random() * errorTypes.length)],
      message: `Error ${i}: Something went wrong`,
      file: Math.random() < 0.7 ? `file${Math.floor(Math.random() * fileCount)}.md` : undefined,
      details: Math.random() < 0.5 ? `Additional details for error ${i}` : undefined
    });
  }

  // Validation passes if no errors
  const validation = {
    passed: errors.length === 0 && movedFiles.every((f) => f.status === 'success'),
    linksChecked: linkCount,
    brokenLinks: Math.floor(Math.random() * 3)
  };

  return {
    movedFiles,
    updatedLinks,
    errors,
    validation
  };
}

/**
 * Verifies that a report contains all required fields and accurate statistics
 */
function verifyReportCompleteness(report, expectedData) {
  const issues = [];

  // Verify required top-level fields
  if (!report.version) issues.push('Missing version field');
  if (!report.generatedAt) issues.push('Missing generatedAt field');
  if (!report.repoRoot) issues.push('Missing repoRoot field');
  if (!report.statistics) issues.push('Missing statistics field');
  if (!report.movedFiles) issues.push('Missing movedFiles field');
  if (!report.updatedLinks) issues.push('Missing updatedLinks field');
  if (!report.errors) issues.push('Missing errors field');
  if (!report.errorsByType) issues.push('Missing errorsByType field');
  if (!report.validation) issues.push('Missing validation field');
  if (!report.summary) issues.push('Missing summary field');

  // Verify statistics accuracy
  if (report.statistics) {
    const stats = report.statistics;
    const expectedSuccessful = expectedData.movedFiles.filter((f) => f.status === 'success').length;
    const expectedFailed = expectedData.movedFiles.filter((f) => f.status === 'failed').length;

    if (stats.totalFilesMoved !== expectedData.movedFiles.length) {
      issues.push(`Incorrect totalFilesMoved: expected ${expectedData.movedFiles.length}, got ${stats.totalFilesMoved}`);
    }

    if (stats.successfulMoves !== expectedSuccessful) {
      issues.push(`Incorrect successfulMoves: expected ${expectedSuccessful}, got ${stats.successfulMoves}`);
    }

    if (stats.failedMoves !== expectedFailed) {
      issues.push(`Incorrect failedMoves: expected ${expectedFailed}, got ${stats.failedMoves}`);
    }

    if (stats.totalLinksUpdated !== expectedData.updatedLinks.length) {
      issues.push(`Incorrect totalLinksUpdated: expected ${expectedData.updatedLinks.length}, got ${stats.totalLinksUpdated}`);
    }

    if (stats.totalErrors !== expectedData.errors.length) {
      issues.push(`Incorrect totalErrors: expected ${expectedData.errors.length}, got ${stats.totalErrors}`);
    }

    if (typeof stats.validationPassed !== 'boolean') {
      issues.push('validationPassed should be a boolean');
    }
  }

  // Verify arrays have correct lengths
  if (report.movedFiles.length !== expectedData.movedFiles.length) {
    issues.push(`Incorrect movedFiles length: expected ${expectedData.movedFiles.length}, got ${report.movedFiles.length}`);
  }

  if (report.updatedLinks.length !== expectedData.updatedLinks.length) {
    issues.push(`Incorrect updatedLinks length: expected ${expectedData.updatedLinks.length}, got ${report.updatedLinks.length}`);
  }

  if (report.errors.length !== expectedData.errors.length) {
    issues.push(`Incorrect errors length: expected ${expectedData.errors.length}, got ${report.errors.length}`);
  }

  // Verify summary is a non-empty string
  if (typeof report.summary !== 'string' || report.summary.length === 0) {
    issues.push('Summary should be a non-empty string');
  }

  return issues;
}

describe('Property Test: Migration Report Generation', () => {
  it('should generate complete report for any migration execution (100 iterations)', async () => {
    const iterations = 100;
    let passedIterations = 0;

    for (let i = 0; i < iterations; i++) {
      // Generate random migration data
      const fileCount = Math.floor(Math.random() * 50) + 1; // 1-50 files
      const linkCount = Math.floor(Math.random() * 100); // 0-99 links
      const errorCount = Math.floor(Math.random() * 10); // 0-9 errors

      const migrationData = generateRandomMigrationData(fileCount, linkCount, errorCount);

      // Generate report
      const report = generateMigrationReport(migrationData, {
        repoRoot: '/test/repo'
      });

      // Verify report completeness
      const issues = verifyReportCompleteness(report, migrationData);

      assert.strictEqual(
        issues.length,
        0,
        `Iteration ${i + 1}: Report has issues: ${issues.join('; ')}`
      );

      passedIterations++;
    }

    // Verify all iterations passed
    assert.strictEqual(
      passedIterations,
      iterations,
      `Expected all ${iterations} iterations to pass, but only ${passedIterations} passed`
    );
  });

  it('should include all required fields in report', () => {
    const migrationData = {
      movedFiles: [
        { source: 'a.md', destination: 'b.md', status: 'success' }
      ],
      updatedLinks: [
        { file: 'b.md', oldLink: '../a.md', newLink: '../b.md', status: 'success' }
      ],
      errors: [],
      validation: { passed: true }
    };

    const report = generateMigrationReport(migrationData);

    // Verify all required fields exist
    assert.ok(report.version, 'Report should have version');
    assert.ok(report.generatedAt, 'Report should have generatedAt');
    assert.ok(report.repoRoot, 'Report should have repoRoot');
    assert.ok(report.statistics, 'Report should have statistics');
    assert.ok(Array.isArray(report.movedFiles), 'Report should have movedFiles array');
    assert.ok(Array.isArray(report.updatedLinks), 'Report should have updatedLinks array');
    assert.ok(Array.isArray(report.errors), 'Report should have errors array');
    assert.ok(report.errorsByType, 'Report should have errorsByType');
    assert.ok(report.validation, 'Report should have validation');
    assert.ok(report.summary, 'Report should have summary');
  });

  it('should calculate statistics accurately', () => {
    const migrationData = {
      movedFiles: [
        { source: 'a.md', destination: 'b.md', status: 'success' },
        { source: 'c.md', destination: 'd.md', status: 'success' },
        { source: 'e.md', destination: 'f.md', status: 'failed', error: 'Failed' }
      ],
      updatedLinks: [
        { file: 'b.md', oldLink: '../a.md', newLink: '../b.md', status: 'success' },
        { file: 'd.md', oldLink: '../c.md', newLink: '../d.md', status: 'success' }
      ],
      errors: [
        { type: 'file_move', message: 'Error 1' },
        { type: 'validation', message: 'Error 2' }
      ],
      validation: { passed: false }
    };

    const report = generateMigrationReport(migrationData);

    assert.strictEqual(report.statistics.totalFilesMoved, 3);
    assert.strictEqual(report.statistics.successfulMoves, 2);
    assert.strictEqual(report.statistics.failedMoves, 1);
    assert.strictEqual(report.statistics.totalLinksUpdated, 2);
    assert.strictEqual(report.statistics.totalErrors, 2);
    assert.strictEqual(report.statistics.validationPassed, false);
  });

  it('should categorize errors by type', () => {
    const migrationData = {
      movedFiles: [],
      updatedLinks: [],
      errors: [
        { type: 'file_move', message: 'Error 1' },
        { type: 'file_move', message: 'Error 2' },
        { type: 'validation', message: 'Error 3' },
        { type: 'git_operation', message: 'Error 4' }
      ],
      validation: { passed: false }
    };

    const report = generateMigrationReport(migrationData);

    assert.ok(report.errorsByType.file_move, 'Should have file_move errors');
    assert.strictEqual(report.errorsByType.file_move.length, 2);
    assert.ok(report.errorsByType.validation, 'Should have validation errors');
    assert.strictEqual(report.errorsByType.validation.length, 1);
    assert.ok(report.errorsByType.git_operation, 'Should have git_operation errors');
    assert.strictEqual(report.errorsByType.git_operation.length, 1);
  });

  it('should generate human-readable summary', () => {
    const migrationData = {
      movedFiles: [
        { source: 'a.md', destination: 'b.md', status: 'success' },
        { source: 'c.md', destination: 'd.md', status: 'failed', error: 'Failed' }
      ],
      updatedLinks: [
        { file: 'b.md', oldLink: '../a.md', newLink: '../b.md', status: 'success' }
      ],
      errors: [
        { type: 'file_move', message: 'Error 1' }
      ],
      validation: { passed: false }
    };

    const report = generateMigrationReport(migrationData);

    // Verify summary is a string
    assert.strictEqual(typeof report.summary, 'string');

    // Verify summary contains key information
    assert.ok(report.summary.includes('Migration Summary'), 'Summary should have title');
    assert.ok(report.summary.includes('Files Moved: 2'), 'Summary should include file count');
    assert.ok(report.summary.includes('Successful: 1'), 'Summary should include successful count');
    assert.ok(report.summary.includes('Failed: 1'), 'Summary should include failed count');
    assert.ok(report.summary.includes('Links Updated: 1'), 'Summary should include link count');
    assert.ok(report.summary.includes('Errors: 1'), 'Summary should include error count');
    assert.ok(report.summary.includes('Validation: FAILED'), 'Summary should include validation status');
    assert.ok(report.summary.includes('Overall Status:'), 'Summary should include overall status');
  });

  it('should handle empty migration data', () => {
    const migrationData = {
      movedFiles: [],
      updatedLinks: [],
      errors: [],
      validation: { passed: true }
    };

    const report = generateMigrationReport(migrationData);

    assert.strictEqual(report.statistics.totalFilesMoved, 0);
    assert.strictEqual(report.statistics.successfulMoves, 0);
    assert.strictEqual(report.statistics.failedMoves, 0);
    assert.strictEqual(report.statistics.totalLinksUpdated, 0);
    assert.strictEqual(report.statistics.totalErrors, 0);
    assert.strictEqual(report.statistics.validationPassed, true);
  });

  it('should write report to file', async () => {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'report-write-test-'));

    try {
      const migrationData = {
        movedFiles: [
          { source: 'a.md', destination: 'b.md', status: 'success' }
        ],
        updatedLinks: [],
        errors: [],
        validation: { passed: true }
      };

      const report = generateMigrationReport(migrationData);
      const outputPath = path.join(tmpDir, 'report.json');

      await writeMigrationReport(report, outputPath);

      // Verify file exists
      assert.ok(await fs.pathExists(outputPath), 'Report file should exist');

      // Verify content
      const content = await fs.readFile(outputPath, 'utf8');
      const parsed = JSON.parse(content);
      assert.deepStrictEqual(parsed.statistics, report.statistics);
    } finally {
      await fs.remove(tmpDir);
    }
  });

  it('should create output directory if it does not exist', async () => {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'report-write-test-'));

    try {
      const migrationData = {
        movedFiles: [],
        updatedLinks: [],
        errors: [],
        validation: { passed: true }
      };

      const report = generateMigrationReport(migrationData);
      const outputPath = path.join(tmpDir, 'nested', 'dir', 'report.json');

      await writeMigrationReport(report, outputPath);

      assert.ok(await fs.pathExists(outputPath), 'Report file should exist in nested directory');
    } finally {
      await fs.remove(tmpDir);
    }
  });

  it('should generate and write report in one operation', async () => {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'report-test-'));

    try {
      const migrationData = {
        movedFiles: [
          { source: 'a.md', destination: 'b.md', status: 'success' }
        ],
        updatedLinks: [
          { file: 'b.md', oldLink: '../a.md', newLink: '../b.md', status: 'success' }
        ],
        errors: [],
        validation: { passed: true }
      };

      const outputPath = path.join(tmpDir, 'report.json');
      const report = await generateAndWriteReport(migrationData, outputPath);

      // Verify return value
      assert.ok(report.statistics);
      assert.strictEqual(report.statistics.totalFilesMoved, 1);

      // Verify file was written
      assert.ok(await fs.pathExists(outputPath));

      // Verify file content matches return value
      const content = await fs.readFile(outputPath, 'utf8');
      const parsed = JSON.parse(content);
      assert.deepStrictEqual(parsed.statistics, report.statistics);
    } finally {
      await fs.remove(tmpDir);
    }
  });

  it('should read report from file', async () => {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'report-read-test-'));

    try {
      const report = {
        version: '1.0.0',
        generatedAt: new Date().toISOString(),
        repoRoot: '/test',
        statistics: {
          totalFilesMoved: 1,
          successfulMoves: 1,
          failedMoves: 0,
          totalLinksUpdated: 0,
          totalErrors: 0,
          validationPassed: true
        },
        movedFiles: [],
        updatedLinks: [],
        errors: [],
        errorsByType: {},
        validation: { passed: true },
        summary: 'Test summary'
      };

      const filePath = path.join(tmpDir, 'report.json');
      await fs.writeFile(filePath, JSON.stringify(report), 'utf8');

      const read = await readMigrationReport(filePath);
      assert.deepStrictEqual(read, report);
    } finally {
      await fs.remove(tmpDir);
    }
  });

  it('should include timestamp in report', () => {
    const migrationData = {
      movedFiles: [],
      updatedLinks: [],
      errors: [],
      validation: { passed: true }
    };

    const before = new Date();
    const report = generateMigrationReport(migrationData);
    const after = new Date();

    assert.ok(report.generatedAt, 'Report should have generatedAt timestamp');
    const generatedAt = new Date(report.generatedAt);
    assert.ok(generatedAt >= before, 'Timestamp should be after test start');
    assert.ok(generatedAt <= after, 'Timestamp should be before test end');
  });

  it('should create migration data from file operations', () => {
    const operations = {
      moves: [
        { source: 'a.md', destination: 'b.md' },
        { source: 'c.md', destination: 'd.md', error: 'Failed' }
      ],
      linkUpdates: [
        { file: 'b.md', oldLink: '../a.md', newLink: '../b.md' }
      ],
      errors: [
        { type: 'validation', message: 'Error 1', file: 'test.md' }
      ],
      validation: { passed: false }
    };

    const migrationData = createMigrationData(operations);

    assert.strictEqual(migrationData.movedFiles.length, 2);
    assert.strictEqual(migrationData.movedFiles[0].status, 'success');
    assert.strictEqual(migrationData.movedFiles[1].status, 'failed');
    assert.strictEqual(migrationData.updatedLinks.length, 1);
    assert.strictEqual(migrationData.errors.length, 1);
    assert.strictEqual(migrationData.validation.passed, false);
  });
});
