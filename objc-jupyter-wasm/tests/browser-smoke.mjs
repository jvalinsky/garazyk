import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const siteRoot = path.resolve(projectRoot, process.argv[2] || 'dist/jupyterlite-smoke');

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch (error) {
  throw new Error(`Playwright is required for browser smoke validation: ${error.message}`);
}

const contentTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.wasm', 'application/wasm'],
  ['.ipynb', 'application/x-ipynb+json; charset=utf-8']
]);

const server = createServer(async (request, response) => {
  const requestUrl = new URL(request.url || '/', 'http://127.0.0.1');
  const normalizedPath = path.normalize(decodeURIComponent(requestUrl.pathname));
  const relativePath = normalizedPath === '/' ? 'index.html' : normalizedPath.replace(/^\/+/, '');
  const filePath = path.resolve(siteRoot, relativePath);

  if (filePath !== siteRoot && !filePath.startsWith(`${siteRoot}${path.sep}`)) {
    response.writeHead(403);
    response.end('forbidden');
    return;
  }

  try {
    const body = await readFile(filePath);
    response.writeHead(200, {
      'content-type': contentTypes.get(path.extname(filePath)) || 'application/octet-stream'
    });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end('not found');
  }
});

await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const { port } = server.address();
const baseUrl = `http://127.0.0.1:${port}`;
const consoleErrors = [];

try {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('console', message => {
    if (message.type() === 'error') {
      consoleErrors.push(message.text());
    }
  });
  page.on('pageerror', error => {
    consoleErrors.push(error.message);
  });

  await page.goto(baseUrl, {
    waitUntil: 'networkidle'
  });
  await page.waitForFunction(() => document.body.dataset.smokeStatus !== 'pending');

  assert.equal(await page.locator('[data-testid="kernel-spec"]').textContent(), 'Objective-C');
  assert.equal(await page.locator('[data-testid="kernel-info-status"]').textContent(), 'ok');
  assert.equal(await page.locator('[data-testid="execute-status"]').textContent(), 'ok');

  const stream = await page.locator('[data-testid="stream-output"]').textContent();
  assert.match(stream || '', /Objective-C WASM smoke executed/);

  const result = await page.locator('[data-testid="result-output"]').textContent();
  assert.match(result || '', /NSLog/);
  assert.match(result || '', /hello browser smoke/);
  assert.deepEqual(consoleErrors, []);

  await browser.close();
  console.log(`objc-jupyter-wasm browser smoke passed at ${baseUrl}`);
} finally {
  await new Promise(resolve => server.close(resolve));
}
