/**
 * Tests for directory cleanup
 */

import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'fs-extra';
import path from 'path';
import os from 'os';
import { removeEmptyDirectories } from './directory-cleanup.js';

async function createFixture() {
  const repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'docs-cleanup-test-'));
  return repoRoot;
}

test('removeEmptyDirectories removes empty subdirectories (deepest first)', async () => {
  const repoRoot = await createFixture();

  try {
    await fs.ensureDir(path.join(repoRoot, 'root/a/b/c'));
    await fs.ensureDir(path.join(repoRoot, 'root/x'));
    await fs.writeFile(path.join(repoRoot, 'root/x/file.txt'), 'not empty', 'utf8');

    const result = await removeEmptyDirectories('root', {
      repoRoot,
      removeRoot: false
    });

    assert.ok(result.removed.includes(path.join('root', 'a', 'b', 'c')));
    assert.ok(result.removed.includes(path.join('root', 'a', 'b')));
    assert.ok(result.removed.includes(path.join('root', 'a')));
    assert.ok(!result.removed.includes('root'));

    assert.ok(await fs.pathExists(path.join(repoRoot, 'root')));
    assert.ok(await fs.pathExists(path.join(repoRoot, 'root/x')));
    assert.ok(await fs.pathExists(path.join(repoRoot, 'root/x/file.txt')));
  } finally {
    await fs.remove(repoRoot);
  }
});

test('removeEmptyDirectories can remove rootDir when removeRoot is true', async () => {
  const repoRoot = await createFixture();

  try {
    await fs.ensureDir(path.join(repoRoot, 'root/sub'));

    const result = await removeEmptyDirectories('root', {
      repoRoot,
      removeRoot: true
    });

    assert.ok(result.removed.includes('root'));
    assert.strictEqual(await fs.pathExists(path.join(repoRoot, 'root')), false);
  } finally {
    await fs.remove(repoRoot);
  }
});

test('removeEmptyDirectories does not remove directories that are not physically empty', async () => {
  const repoRoot = await createFixture();

  try {
    await fs.ensureDir(path.join(repoRoot, 'git-only/.git'));
    await fs.writeFile(path.join(repoRoot, 'git-only/.git/config'), 'config', 'utf8');

    const result = await removeEmptyDirectories('git-only', {
      repoRoot,
      removeRoot: true
    });

    assert.ok(!result.removed.includes('git-only'));
    assert.ok(result.skipped.some((s) => s.dir === 'git-only'));
    assert.strictEqual(await fs.pathExists(path.join(repoRoot, 'git-only')), true);
  } finally {
    await fs.remove(repoRoot);
  }
});
