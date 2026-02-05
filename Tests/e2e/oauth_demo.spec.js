const puppeteer = require('puppeteer');

(async () => {
    console.log('[E2E] Starting OAuth Demo Test');
    const browser = await puppeteer.launch({
        headless: "new",
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    const diagnostics = [];
    const contexts = [];
    const startUrl = 'http://localhost:2583/oauth-demo/';

    function attachDiagnostics(page, label) {
        const diag = {
            label,
            page,
            consoleLogs: [],
            pageErrors: [],
            requestFailures: [],
            responseErrors: []
        };

        page.on('console', msg => {
            const entry = `[${msg.type()}] ${msg.text()}`;
            console.log(`[${label}] PAGE LOG:`, entry);
            diag.consoleLogs.push(entry);
        });
        page.on('pageerror', err => {
            const entry = err && err.message ? err.message : String(err);
            diag.pageErrors.push(entry);
        });
        page.on('requestfailed', req => {
            diag.requestFailures.push(`${req.method()} ${req.url()} => ${req.failure()?.errorText || 'unknown error'}`);
        });
        page.on('response', res => {
            if (res.status() >= 400) {
                diag.responseErrors.push(`${res.status()} ${res.request().method()} ${res.url()}`);
            }
        });

        diagnostics.push(diag);
        return diag;
    }

    async function createContext(label) {
        const context = await browser.createBrowserContext();
        const page = await context.newPage();
        contexts.push(context);
        attachDiagnostics(page, label);
        return page;
    }

    async function loginWithHandle(handle, label) {
        const page = await createContext(label);
        console.log(`[E2E] Navigating to ${startUrl} (${label})`);
        await page.goto(startUrl, { waitUntil: 'networkidle0' });
        console.log(`[E2E] Entering handle and clicking login (${label})...`);
        const handleInput = await page.$('#handle');
        await handleInput.click({ clickCount: 3 });
        await handleInput.press('Backspace');
        await page.type('#handle', handle);
        await Promise.all([
            page.click('#btn-login'),
            page.waitForNavigation({ waitUntil: 'networkidle0' })
        ]);
        console.log(`[E2E] Current URL (${label}): ${page.url()}`);
        console.log(`[E2E] Waiting for token exchange (${label})...`);
        await page.waitForSelector('#session-section', { visible: true, timeout: 5000 });
        return page;
    }

    async function runGetSession(page, label) {
        console.log(`[E2E] Testing API session (${label})...`);
        await page.click('#btn-test-session');
        await page.waitForSelector('#api-result', { visible: true });
        const apiResult = await page.$eval('#api-result', el => el.textContent);
        if (!apiResult.includes('did')) {
            throw new Error(`API result does not contain DID (${label})`);
        }
        const parsed = JSON.parse(apiResult);
        if (!parsed.did) {
            throw new Error(`API result missing did field (${label})`);
        }
        console.log(`[E2E] API Session Verified (${label})`);
        return parsed.did;
    }

    async function createPost(page, label, text) {
        await page.evaluate(value => {
            const input = document.querySelector('#post-text');
            if (input) input.value = value;
        }, text);
        await page.click('#btn-create-post');
        await page.waitForSelector('#post-result', { visible: true });
        const postResult = await page.$eval('#post-result', el => el.textContent);
        const parsed = JSON.parse(postResult);
        if (!parsed.uri || !parsed.cid) {
            throw new Error(`Post result does not include uri/cid (${label})`);
        }
        console.log(`[E2E] Post created (${label}):`, text);
        console.log(`[E2E] Post created result (${label}):`, postResult);
        return parsed;
    }

    async function createReply(page, label, text, parent) {
        const result = await page.evaluate(async (payload) => {
            const input = document.querySelector('#post-text');
            if (input) input.value = payload.text;
            return window.oauthDemo.createPostWithReply(payload.reply);
        }, { text, reply: parent });
        if (!result || !result.uri || !result.cid) {
            throw new Error(`Reply result does not include uri/cid (${label})`);
        }
        console.log(`[E2E] Reply created (${label}):`, text);
        console.log(`[E2E] Reply created result (${label}):`, JSON.stringify(result));
        return result;
    }

    async function sleepMs(ms) {
        await new Promise(resolve => setTimeout(resolve, ms));
    }

    async function logout(page, label) {
        await Promise.all([
            page.click('#btn-logout'),
            page.waitForNavigation({ waitUntil: 'networkidle0' })
        ]);
        await page.waitForSelector('#btn-list-records', { visible: true });
        console.log(`[E2E] Logged out (${label})`);
    }

    async function fetchJson(url, options, label) {
        const response = await fetch(url, options);
        const text = await response.text();
        let data = null;
        try {
            data = text ? JSON.parse(text) : null;
        } catch (err) {
            throw new Error(`[${label}] Failed to parse JSON from ${url}: ${text}`);
        }
        if (!response.ok) {
            throw new Error(`[${label}] HTTP ${response.status} from ${url}: ${JSON.stringify(data)}`);
        }
        return data;
    }

    async function loginAsAdmin(label) {
        console.log(`[${label}] Logging in as admin...`);
        const response = await fetch('http://localhost:2583/admin/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ password: 'admin123' })
        });
        const data = await response.json();
        if (!response.ok || !data.token) {
            throw new Error(`[${label}] Admin login failed: ${JSON.stringify(data)}`);
        }
        console.log(`[${label}] Admin login successful`);
        return data.token;
    }

    async function adminModerateAccount(did, reason, adminToken, label) {
        console.log(`[${label}] Moderating account: ${did}`);
        const response = await fetch('http://localhost:2583/xrpc/com.atproto.admin.moderateAccount', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${adminToken}`
            },
            body: JSON.stringify({ did, reason })
        });
        const data = await response.json();
        if (!response.ok) {
            throw new Error(`[${label}] moderateAccount failed: ${JSON.stringify(data)}`);
        }
        console.log(`[${label}] Account moderated: ${did}`);
        return data;
    }

    async function adminTakeDownAccount(did, reason, adminToken, label) {
        console.log(`[${label}] Taking down account: ${did}`);
        const response = await fetch('http://localhost:2583/xrpc/com.atproto.admin.takeDownAccount', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${adminToken}`
            },
            body: JSON.stringify({ did, reason })
        });
        const data = await response.json();
        if (!response.ok) {
            throw new Error(`[${label}] takeDownAccount failed: ${JSON.stringify(data)}`);
        }
        console.log(`[${label}] Account taken down: ${did}`);
        return data;
    }

    async function adminGetTakedown(did, adminToken, label) {
        console.log(`[${label}] Getting takedown status: ${did}`);
        const response = await fetch('http://localhost:2583/xrpc/com.atproto.admin.getAccountTakedown', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${adminToken}`
            },
            body: JSON.stringify({ did })
        });
        const data = await response.json();
        if (!response.ok) {
            throw new Error(`[${label}] getAccountTakedown failed: ${JSON.stringify(data)}`);
        }
        console.log(`[${label}] Takedown status: ${data.applied}`);
        return data;
    }

    try {
        const user1Page = await loginWithHandle('e2e1.test', 'user1');
        const user2Page = await loginWithHandle('e2e2.test', 'user2');

        const user1Did = await runGetSession(user1Page, 'user1');
        const user2Did = await runGetSession(user2Page, 'user2');

        const post1Text = `E2E user1 post ${Date.now()}`;
        const post2Text = `E2E user1 post extra ${Date.now()}`;
        const post1 = await createPost(user1Page, 'user1', post1Text);
        await new Promise(resolve => setTimeout(resolve, 25));
        let post2 = null;
        await sleepMs(10);
        for (let attempt = 0; attempt < 5; attempt++) {
            while (Date.now() === Number(post1Text.split(' ').pop())) {
                await sleepMs(2);
            }
            post2 = await createPost(user1Page, 'user1', post2Text);
            if (post2.uri !== post1.uri) {
                break;
            }
            await sleepMs(5);
        }
        if (!post2 || post2.uri === post1.uri) {
            throw new Error('User1 posts returned identical uris; expected unique records');
        }

        const replyText = `E2E user2 reply ${Date.now()}`;
        const replyRef = {
            root: { uri: post1.uri, cid: post1.cid },
            parent: { uri: post1.uri, cid: post1.cid }
        };
        await sleepMs(10);
        const reply = await createReply(user2Page, 'user2', replyText, replyRef);
        const user2PostText = `E2E user2 post ${Date.now()}`;
        await sleepMs(10);
        await createPost(user2Page, 'user2', user2PostText);

        const adminToken = await loginAsAdmin('E2E');

        await adminModerateAccount(user2Did, 'ToS violation: abusive comment', adminToken, 'E2E');

        await adminTakeDownAccount(user2Did, 'ToS violation: abusive comment', adminToken, 'E2E');

        const takedownStatus = await adminGetTakedown(user2Did, adminToken, 'E2E');

        if (!takedownStatus.applied) {
            throw new Error('Expected account takedown to be applied');
        }
        console.log('[E2E] Account takedown applied for', user2Did);

        let suspendedError = null;
        try {
            const suspendedText = `E2E user2 suspended post ${Date.now()}`;
            await createPost(user2Page, 'user2', suspendedText);
        } catch (err) {
            suspendedError = err;
        }
        if (!suspendedError) {
            throw new Error('Expected suspended user to fail creating a post');
        }
        console.log('[E2E] Suspended user blocked from posting');

        await logout(user1Page, 'user1');
        await logout(user2Page, 'user2');

        const user1Records = await fetchJson(`http://localhost:2583/xrpc/com.atproto.repo.listRecords?repo=${encodeURIComponent(user1Did)}&collection=app.bsky.feed.post&limit=50`, {}, 'listRecords-user1');
        const user2Records = await fetchJson(`http://localhost:2583/xrpc/com.atproto.repo.listRecords?repo=${encodeURIComponent(user2Did)}&collection=app.bsky.feed.post&limit=50`, {}, 'listRecords-user2');

        const user1Values = JSON.stringify(user1Records);
        const user2Values = JSON.stringify(user2Records);

        if (!user1Values.includes(post1Text) || !user1Values.includes(post2Text)) {
            throw new Error('User1 records missing expected posts');
        }
        if (!user2Values.includes(replyText) || !user2Values.includes(user2PostText)) {
            throw new Error('User2 records missing expected posts');
        }
        if (post1.uri === replyRef.parent.uri && !user2Values.includes(replyText)) {
            throw new Error('Reply text missing in user2 records');
        }
        console.log('[E2E] Records verified for both users');
        console.log('[E2E] Reply created:', JSON.stringify(reply));

        console.log('[E2E] Test Passed!');
    } catch (error) {
        console.error('[E2E] Test Failed:', error);
        for (const diag of diagnostics) {
            const url = diag.page ? diag.page.url() : 'unknown';
            console.error(`[E2E] Diagnostic for ${diag.label} (url=${url})`);
            if (diag.pageErrors.length) {
                console.error(`[E2E] Page Errors (${diag.label}):`, diag.pageErrors.slice(-10));
            }
            if (diag.requestFailures.length) {
                console.error(`[E2E] Request Failures (${diag.label}):`, diag.requestFailures.slice(-10));
            }
            if (diag.responseErrors.length) {
                console.error(`[E2E] HTTP Errors (${diag.label}):`, diag.responseErrors.slice(-10));
            }
            if (diag.consoleLogs.length) {
                console.error(`[E2E] Console Logs (${diag.label}):`, diag.consoleLogs.slice(-10));
            }
        }
        process.exit(1);
    } finally {
        for (const context of contexts) {
            try {
                await context.close();
            } catch (err) {
                console.error('[E2E] Failed to close context:', err.message);
            }
        }
        await browser.close();
    }
})();
