const puppeteer = require('puppeteer');

(async () => {
    console.log('[E2E] Starting OAuth Demo Test');
    const browser = await puppeteer.launch({
        headless: "new",
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    const page = await browser.newPage();
    const consoleLogs = [];
    const pageErrors = [];
    const requestFailures = [];
    const responseErrors = [];

    page.on('console', msg => {
        const entry = `[${msg.type()}] ${msg.text()}`;
        console.log('PAGE LOG:', entry);
        consoleLogs.push(entry);
    });
    page.on('pageerror', err => {
        const entry = err && err.message ? err.message : String(err);
        pageErrors.push(entry);
    });
    page.on('requestfailed', req => {
        requestFailures.push(`${req.method()} ${req.url()} => ${req.failure()?.errorText || 'unknown error'}`);
    });
    page.on('response', res => {
        if (res.status() >= 400) {
            responseErrors.push(`${res.status()} ${res.request().method()} ${res.url()}`);
        }
    });

    try {
        // 1. Navigate to Demo Page
        const startUrl = 'http://localhost:2583/oauth-demo/';
        console.log(`[E2E] Navigating to ${startUrl}`);
        await page.goto(startUrl, {
            waitUntil: 'networkidle0'
        });

        // 2. Enter Handle and Login
        console.log('[E2E] Entering handle and clicking login...');
        const handleInput = await page.$('#handle');
        await handleInput.click({ clickCount: 3 }); // Select all
        await handleInput.press('Backspace'); // Clear
        await page.type('#handle', 'e2e.test');
        await Promise.all([
            page.click('#btn-login'),
            page.waitForNavigation({ waitUntil: 'networkidle0' })
        ]);

        // 3. Verify Redirect to Authorize Page (should happen automatically if server logic matches)
        // Note: The demo client redirects to /oauth/authorize. 
        // If the PDS requires user interaction on the authorize page (consent), we'd need to handle it.
        // But currently, OAuth2Handler.m redirects back immediately for test-client? 
        // Let's check logs. Ah, OAuth2Handler.m redirects immediately if no consent UI is implemented.

        console.log(`[E2E] Current URL: ${page.url()}`);

        // Wait for callback to process
        console.log('[E2E] Waiting for token exchange...');
        await page.waitForSelector('#session-section', { visible: true, timeout: 5000 });

        // 4. Verify Session Data
        const tokenDisplay = await page.$eval('#token-display', el => el.textContent);
        if (!tokenDisplay.includes('access_token')) {
            throw new Error('Access token not found in display');
        }
        console.log('[E2E] Token received successfully');

        // 5. Test API Session to capture DID
        console.log('[E2E] Testing API session...');
        await page.click('#btn-test-session');
        await page.waitForSelector('#api-result', { visible: true });

        const apiResult = await page.$eval('#api-result', el => el.textContent);
        if (!apiResult.includes('did')) {
            throw new Error('API result does not contain DID');
        }
        console.log('[E2E] API Session Verified');

        // 6. Create a post while authenticated
        const postText = `E2E post ${Date.now()}`;
        await page.type('#post-text', postText);
        await page.click('#btn-create-post');
        await page.waitForSelector('#post-result', { visible: true });

        const postResult = await page.$eval('#post-result', el => el.textContent);
        if (!postResult.includes('uri') && !postResult.includes('cid')) {
            throw new Error('Post result does not include uri/cid');
        }
        console.log('[E2E] Post created text:', postText);
        console.log('[E2E] Post created result:', postResult);

        // 7. Logout
        await Promise.all([
            page.click('#btn-logout'),
            page.waitForNavigation({ waitUntil: 'networkidle0' })
        ]);
        await page.waitForSelector('#btn-list-records', { visible: true });

        // 8. List public records after logout
        await page.click('#btn-list-records');
        await page.waitForSelector('#records-result', { visible: true });

        const recordsResult = await page.$eval('#records-result', el => el.textContent);
        if (!recordsResult.includes(postText)) {
            throw new Error('Public records do not include the created post');
        }
        console.log('[E2E] Public records include post:', postText);
        console.log('[E2E] Records response:', recordsResult);

        console.log('[E2E] Test Passed!');
    } catch (error) {
        console.error('[E2E] Test Failed:', error);
        console.error('[E2E] Current URL:', page.url());
        if (pageErrors.length) {
            console.error('[E2E] Page Errors:', pageErrors.slice(-10));
        }
        if (requestFailures.length) {
            console.error('[E2E] Request Failures:', requestFailures.slice(-10));
        }
        if (responseErrors.length) {
            console.error('[E2E] HTTP Errors:', responseErrors.slice(-10));
        }
        if (consoleLogs.length) {
            console.error('[E2E] Console Logs (tail):', consoleLogs.slice(-10));
        }
        process.exit(1);
    } finally {
        await browser.close();
    }
})();
