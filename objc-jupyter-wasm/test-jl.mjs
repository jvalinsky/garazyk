import { chromium } from 'playwright';
import http from 'http';
import handler from 'serve-handler';

const server = http.createServer((request, response) => {
  return handler(request, response, {
    public: 'dist/jupyterlite'
  });
});

server.listen(51151, async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  
  page.on('console', msg => console.log(`[Browser Console] ${msg.type()}: ${msg.text()}`));
  page.on('pageerror', err => console.error(`[Browser Error] ${err}`));
  page.on('requestfailed', request => console.log(`[Network Error] ${request.url()} : ${request.failure().errorText}`));

  console.log("Navigating to JupyterLite notebook...");
  await page.goto('http://localhost:51151/lab/index.html');
  
  await page.waitForTimeout(5000);

  const urls = await page.evaluate(() => {
    const pc = window._JUPYTERLAB[0] ? window._JUPYTERLAB[0] : null; // Hacky, let's just use document.body.dataset
    return {
      baseUrl: document.body.dataset.baseUrl,
      wsUrl: document.body.dataset.wsUrl
    };
  });
  console.log("URLs from DOM:", urls);
  
  console.log("Double clicking hello.ipynb...");
  await page.locator('text=hello.ipynb').dblclick();

  await page.waitForTimeout(10000);
  
  await page.screenshot({ path: 'screenshot2.png' });
  console.log("Screenshot saved.");

  await page.waitForTimeout(1000);
  
  console.log("Done waiting, closing...");
  await browser.close();
  server.close();
});
