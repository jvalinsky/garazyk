import { API } from './api.js';
import { CIDDecoder } from './cid.js';
import { renderDidDocument, renderDidSummary } from './did.js';
import { renderPlcOperations } from './plc.js';
import * as Poster from './poster.js';

const PLC_BASE = 'http://localhost:2582';

console.log('ui.js loading...');

let currentDid = null;
let currentHandle = null;
let currentCollection = null;

window.viewCollection = (collection) => {
    console.log('window.viewCollection called for collection:', collection);
    currentCollection = collection;
    showRecords(collection);
};

window.viewRecordDetail = (uri) => {
    console.log('window.viewRecordDetail called for uri:', uri);
    showRecordDetail(uri);
};

window.viewFeedPosts = () => {
    if (!currentDid) {
        alert('Please select an account first.');
        return;
    }
    showFeedPosts();
};

window.viewFeedLikes = () => {
    if (!currentDid) {
        alert('Please select an account first.');
        return;
    }
    showFeedLikes();
};

window.viewFeedReposts = () => {
    if (!currentDid) {
        alert('Please select an account first.');
        return;
    }
    showFeedReposts();
};

window.viewGraphFollows = () => {
    if (!currentDid) {
        alert('Please select an account first.');
        return;
    }
    showGraphFollows();
};

window.viewActorProfile = () => {
    if (!currentDid) {
        alert('Please select an account first.');
        return;
    }
    showActorProfile();
};

document.addEventListener('DOMContentLoaded', () => {
    console.log('ui.js: DOM fully loaded and parsed');
    try {
        init();
        console.log('ui.js: Initialization successful');
    } catch (error) {
        console.error('ui.js: Initialization failed:', error);
    }
});

function init() {
    console.log('ui.js: Initializing UI components...');

    const lookupInput = document.getElementById('lookup-input');
    if (lookupInput) {
        lookupInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') handleLookup();
        });
    }

    const cidDecodeBtn = document.getElementById('cid-decode-btn');
    if (cidDecodeBtn) {
        cidDecodeBtn.addEventListener('click', handleCidDecode);
    }

    const cidInput = document.getElementById('cid-input');
    if (cidInput) {
        cidInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') handleCidDecode();
        });
    }

    const backCollections = document.getElementById('back-collections');
    if (backCollections) {
        backCollections.addEventListener('click', showCollectionsSection);
    }

    const backRecords = document.getElementById('back-records');
    if (backRecords) {
        backRecords.addEventListener('click', () => {
            window.openWindow('records');
        });
    }

    // Menubar linking
    const menuAccounts = document.getElementById('menu-accounts');
    if (menuAccounts) {
        menuAccounts.addEventListener('click', (e) => {
            e.preventDefault();
            document.getElementById('win-accounts').style.display = 'block';
        });
    }

    const menuDetails = document.getElementById('menu-details');
    if (menuDetails) {
        menuDetails.addEventListener('click', (e) => {
            e.preventDefault();
            window.openWindow('did-doc');
        });
    }

    // Poster window
    initPoster();

    window.openWindow('did-doc');
    loadAccounts();
    // Initialize draggability for all windows
    document.querySelectorAll('.window').forEach(makeDraggable);
}


async function loadAccounts() {
    const list = document.getElementById('account-list');
    list.innerHTML = '<li class="loading">Loading...</li>';

    const result = await API.getAccounts();

    if (result.accounts && result.accounts.length > 0) {
        list.innerHTML = '';
        for (const account of result.accounts) {
            const li = document.createElement('li');
            li.className = 'account-item';
            li.dataset.did = account.did;
            li.dataset.handle = account.handle || '';
            li.innerHTML = `
                <span style="font-size:14px">👤</span>
                <span class="account-handle">${escapeHtml(account.handle || account.did)}</span>
            `;
            li.addEventListener('click', () => selectAccount(account));
            list.appendChild(li);
        }
    } else {
        list.innerHTML = '<li class="empty" style="padding:5px; border:none; background:none;">No accounts found</li>';
    }
}

async function selectAccount(account) {
    document.querySelectorAll('.account-item').forEach(li => {
        li.classList.remove('active');
        if (li.dataset.did === account.did) {
            li.classList.add('active');
        }
    });

    currentDid = account.did;
    currentHandle = account.handle || '';

    document.getElementById('did-content').innerHTML = '<p class="loading">Loading DID document...</p>';
    document.getElementById('plc-content').innerHTML = '<p class="loading">Loading PLC operations...</p>';
    document.getElementById('collections-content').innerHTML = '<p class="loading">Loading collections...</p>';

    const activeSection = document.querySelector('.doc-section.active');
    const currentSection = activeSection ? activeSection.id : 'did-doc';

    if (currentSection === 'feed-posts') {
        await showDidDocument(account.did);
        showFeedPosts();
    } else if (currentSection === 'feed-likes') {
        await showDidDocument(account.did);
        showFeedLikes();
    } else if (currentSection === 'feed-reposts') {
        await showDidDocument(account.did);
        showFeedReposts();
    } else if (currentSection === 'graph-follows') {
        await showDidDocument(account.did);
        showGraphFollows();
    } else if (currentSection === 'actor-profile') {
        await showDidDocument(account.did);
        showActorProfile();
    } else {
        window.openWindow('did-doc');
        await showDidDocument(account.did);
    }
}


async function handleLookup() {
    const input = document.getElementById('lookup-input').value.trim();
    if (!input) return;

    document.getElementById('lookup-input').disabled = true;

    // Reset view
    document.querySelectorAll('.account-item').forEach(li => li.classList.remove('active'));
    document.getElementById('did-content').innerHTML = '<p class="loading">Looking up DID/handle...</p>';

    const result = await API.lookup(input);
    document.getElementById('lookup-input').disabled = false;

    if (result.error) {
        alert('DID/handle not found: ' + result.error);
        return;
    }

    currentDid = result.did;

    // Highlight if it's in our list
    document.querySelectorAll('.account-item').forEach(li => {
        if (li.dataset.did === result.did) {
            li.classList.add('active');
        }
    });

    window.openWindow('did-doc');
    await showDidDocument(result.did);
}


async function showDidDocument(did) {
    const didContent = document.getElementById('did-content');
    const plcContent = document.getElementById('plc-content');
    const collectionsContent = document.getElementById('collections-content');

    // Parallel API calls
    const [doc, ops, describe] = await Promise.all([
        API.getDidDocument(did),
        API.getPlcLog(did),
        API.getRepoDescribe(did)
    ]);

    if (doc.error) {
        didContent.innerHTML = `<p class="error">${escapeHtml(doc.error)}</p>`;
    } else {
        didContent.innerHTML = renderDidSummary(doc);
    }

    plcContent.innerHTML = renderPlcOperations(ops);
    renderCollections(describe);
}

function renderCollections(describe) {
    console.log('renderCollections called with:', describe);
    const content = document.getElementById('collections-content');

    if (describe.error) {
        content.innerHTML = `<p class="error">${escapeHtml(describe.error)}</p>`;
        return;
    }

    if (!describe.collections || describe.collections.length === 0) {
        content.innerHTML = '<p class="empty">No collections found</p>';
        return;
    }

    let html = `
        <p class="description">
            This repository contains <strong>${describe.collections.length}</strong> collections. 
            Select a collection below to browse its records.
        </p>
        <table class="param-table">
            <thead>
                <tr><th>Collection NSID</th><th>Action</th></tr>
            </thead>
            <tbody>
    `;

    for (const collection of describe.collections) {
        html += `
            <tr>
                <td><code>${escapeHtml(collection)}</code></td>
                <td><button class="btn-secondary" onclick="window.viewCollection('${escapeHtml(collection)}')">View Records</button></td>
            </tr>
        `;
    }

    html += '</tbody></table>';
    content.innerHTML = html;
}

async function showRecords(collection) {
    console.log('showRecords called for collection:', collection);
    if (!currentDid) {
        console.error('No currentDid set');
        return;
    }

    window.openWindow('records');


    document.getElementById('records-title').textContent = collection;

    const content = document.getElementById('records-content');
    content.innerHTML = '<p class="loading">Loading records...</p>';

    try {
        const result = await API.listRecords(currentDid, collection, { limit: 20 });
        console.log('listRecords result:', result);
        renderRecordsList(result.records, collection);
    } catch (e) {
        console.error('Failed to list records:', e);
        content.innerHTML = `<p class="error">Error loading records: ${escapeHtml(e.message)}</p>`;
    }
}

function renderRecordsList(records, collection) {
    console.log('renderRecordsList called with:', records);
    const content = document.getElementById('records-content');

    if (!records || records.length === 0) {
        content.innerHTML = `<p class="empty">No records in collection ${escapeHtml(collection)}</p>`;
        return;
    }

    let html = `
        <p class="description">Found <strong>${records.length}</strong> records in ${escapeHtml(collection)}.</p>
        <table>
            <thead>
                <tr><th>RKey</th><th>CID</th><th>Action</th></tr>
            </thead>
            <tbody>
    `;

    for (const record of records) {
        const displayCid = record.cid ? record.cid.slice(0, 12) + '...' : 'N/A';
        html += `
            <tr>
                <td><code>${escapeHtml(record.rkey)}</code></td>
                <td><code title="${escapeHtml(record.cid || '')}">${escapeHtml(displayCid)}</code></td>
                <td><button class="btn-secondary" onclick="window.viewRecordDetail('${escapeHtml(record.uri)}')">View Detail</button></td>
            </tr>
        `;
    }

    html += '</tbody></table>';
    content.innerHTML = html;
}

async function showRecordDetail(uri) {
    console.log('showRecordDetail called for uri:', uri);
    if (!currentDid) {
        console.error('No currentDid set');
        return;
    }

    window.openWindow('record-detail');


    document.getElementById('record-title').textContent = uri;
    document.getElementById('record-content').textContent = 'Loading...';

    try {
        const record = await API.getRecord(uri);
        console.log('getRecord result:', record);
        if (record.error) {
            document.getElementById('record-content').textContent = record.error;
        } else {
            document.getElementById('record-content').textContent = JSON.stringify(record, null, 2);
        }
    } catch (e) {
        console.error('Failed to get record:', e);
        document.getElementById('record-content').textContent = 'Error: ' + e.message;
    }
}

async function showFeedPosts() {
    window.openWindow('feed-posts');
    const content = document.getElementById('feed-posts-content');
    content.innerHTML = '<p class="loading">Loading posts...</p>';

    const result = await API.getFeedPosts(currentDid, { limit: 20 });

    if (!result.posts || result.posts.length === 0) {
        content.innerHTML = '<p class="empty">No posts found</p>';
        return;
    }

    let html = '<p class="description">Found <strong>' + result.posts.length + '</strong> posts.</p>';
    for (const post of result.posts) {
        const text = escapeHtml(post.record?.text || '');
        const date = post.record?.createdAt || '';
        const handle = escapeHtml(post.author?.handle || post.author?.did || '');
        html += '<div style="border:1px solid #999; padding:8px; margin-bottom:8px; background:#fff;">';
        html += '<div style="display:flex; justify-content:space-between; margin-bottom:4px;">';
        html += '<strong>' + handle + '</strong>';
        html += '<span style="color:#666;">' + escapeHtml(date) + '</span>';
        html += '</div>';
        html += '<div style="white-space:pre-wrap;">' + text + '</div>';
        html += '</div>';
    }

    content.innerHTML = html;
}

async function showFeedLikes() {
    window.openWindow('feed-likes');
    const content = document.getElementById('feed-likes-content');
    content.innerHTML = '<p class="loading">Loading likes...</p>';

    const result = await API.getFeedLikes(currentDid, { limit: 20 });

    if (!result.likes || result.likes.length === 0) {
        content.innerHTML = '<p class="empty">No likes found</p>';
        return;
    }

    let html = '<p class="description">Found <strong>' + result.likes.length + '</strong> likes.</p>';
    html += '<table class="param-table"><thead><tr><th>Subject</th><th>Author</th><th>Date</th></tr></thead><tbody>';
    for (const like of result.likes) {
        const subjectUri = escapeHtml(like.subject?.uri || '');
        const subjectHandle = escapeHtml(like.subject?.author?.handle || like.subject?.author?.did || '');
        const date = escapeHtml(like.createdAt || '');
        html += '<tr>';
        html += '<td><code>' + subjectUri + '</code></td>';
        html += '<td>' + subjectHandle + '</td>';
        html += '<td>' + date + '</td>';
        html += '</tr>';
    }
    html += '</tbody></table>';

    content.innerHTML = html;
}

async function showFeedReposts() {
    window.openWindow('feed-reposts');
    const content = document.getElementById('feed-reposts-content');
    content.innerHTML = '<p class="loading">Loading reposts...</p>';

    const result = await API.getFeedReposts(currentDid, { limit: 20 });

    if (!result.reposts || result.reposts.length === 0) {
        content.innerHTML = '<p class="empty">No reposts found</p>';
        return;
    }

    let html = '<p class="description">Found <strong>' + result.reposts.length + '</strong> reposts.</p>';
    html += '<table class="param-table"><thead><tr><th>Subject</th><th>Author</th><th>Date</th></tr></thead><tbody>';
    for (const repost of result.reposts) {
        const subjectUri = escapeHtml(repost.subject?.uri || '');
        const subjectHandle = escapeHtml(repost.subject?.author?.handle || repost.subject?.author?.did || '');
        const date = escapeHtml(repost.createdAt || '');
        html += '<tr>';
        html += '<td><code>' + subjectUri + '</code></td>';
        html += '<td>' + subjectHandle + '</td>';
        html += '<td>' + date + '</td>';
        html += '</tr>';
    }
    html += '</tbody></table>';

    content.innerHTML = html;
}

async function showGraphFollows() {
    window.openWindow('graph-follows');
    const content = document.getElementById('graph-follows-content');
    content.innerHTML = '<p class="loading">Loading follows...</p>';

    const result = await API.getFollows(currentDid, { limit: 50 });

    if (!result.actors || result.actors.length === 0) {
        content.innerHTML = '<p class="empty">No follows found</p>';
        return;
    }

    let html = '<p class="description">Following <strong>' + result.actors.length + '</strong> accounts.</p>';
    html += '<table class="param-table"><thead><tr><th>Handle</th><th>DID</th><th>Display Name</th></tr></thead><tbody>';
    for (const actor of result.actors) {
        html += '<tr>';
        html += '<td><strong>' + escapeHtml(actor.handle) + '</strong></td>';
        html += '<td><code>' + escapeHtml(actor.did) + '</code></td>';
        html += '<td>' + escapeHtml(actor.displayName || '') + '</td>';
        html += '</tr>';
    }
    html += '</tbody></table>';

    content.innerHTML = html;
}

async function showActorProfile() {
    window.openWindow('actor-profile');
    const content = document.getElementById('actor-profile-content');
    content.innerHTML = '<p class="loading">Loading profile...</p>';

    const result = await API.getActorProfile(currentDid);

    if (result.error) {
        content.innerHTML = '<p class="error">' + escapeHtml(result.error) + '</p>';
        return;
    }

    let html = '<div style="border:1px solid #999; padding:10px; background:#fff;">';
    html += '<div style="margin-bottom:10px;">';
    html += '<div style="font-size:16px; font-weight:bold;">' + escapeHtml(result.displayName || result.handle) + '</div>';
    html += '<div style="color:#666;">@' + escapeHtml(result.handle) + '</div>';
    html += '<div style="color:#999;"><code>' + escapeHtml(result.did) + '</code></div>';
    html += '</div>';
    if (result.description) {
        html += '<div style="margin-bottom:10px; white-space:pre-wrap;">' + escapeHtml(result.description) + '</div>';
    }
    html += '<div style="display:flex; gap:20px;">';
    html += '<div><strong>' + (result.postsCount || 0) + '</strong> posts</div>';
    html += '<div><strong>' + (result.followsCount || 0) + '</strong> following</div>';
    html += '<div><strong>' + (result.followersCount || 0) + '</strong> followers</div>';
    html += '</div>';
    if (result.createdAt) {
        html += '<div style="margin-top:10px; color:#999;">Joined: ' + escapeHtml(result.createdAt) + '</div>';
    }
    html += '</div>';

    content.innerHTML = html;
}

async function handleCidDecode() {
    const cid = document.getElementById('cid-input').value.trim();
    if (!cid) return;

    const resultEl = document.getElementById('cid-result');
    resultEl.innerHTML = '<p class="loading">Decoding...</p>';

    try {
        const decoded = CIDDecoder.decode(cid);
        if (decoded.error) {
            resultEl.innerHTML = `<p class="error">${escapeHtml(decoded.error)}</p>`;
            return;
        }

        // Custom render for the new style
        let html = '<div style="margin-top:20px">';
        html += `<h3>CID Version ${decoded.version}</h3>`;
        html += '<table><tr><th>Property</th><th>Value</th></tr>';
        html += `<tr><td>Codec</td><td>${decoded.codecName} (${decoded.codec})</td></tr>`;
        html += `<tr><td>Hash Algorithm</td><td>${decoded.multihash.algorithm} (${decoded.multihash.algorithmCode})</td></tr>`;
        html += `<tr><td>Digest Size</td><td>${decoded.multihash.size} bytes</td></tr>`;
        html += '</table>';
        html += '</div>';

        resultEl.innerHTML = html;
    } catch (e) {
        resultEl.innerHTML = `<p class="error">${escapeHtml(e.message)}</p>`;
    }
}

function showSection(sectionId) {
    window.openWindow(sectionId);
}


function showCollectionsSection() {
    window.openWindow('collections');
}


// --- Poster (OAuth) ---

function initPoster() {
    // Check for OAuth callback on page load
    Poster.handleOAuthCallback().then(result => {
        if (result && !result.error && result.did) {
            showPosterSession(result.did);
            document.getElementById('win-poster').style.display = 'block';
        } else if (result && result.error) {
            showPosterResult('Error: ' + result.error, true);
            document.getElementById('win-poster').style.display = 'block';
        }
    });

    // Restore session if exists
    const session = Poster.getSession();
    if (session) {
        showPosterSession(session.did);
    }

    // Menu item
    const menuPoster = document.getElementById('menu-poster');
    if (menuPoster) {
        menuPoster.addEventListener('click', (e) => {
            e.preventDefault();
            document.getElementById('win-poster').style.display = 'block';
        });
    }

    // Login button
    const loginBtn = document.getElementById('poster-login-btn');
    if (loginBtn) {
        loginBtn.addEventListener('click', () => {
            const handle = document.getElementById('poster-handle').value.trim();
            if (!handle) return;
            Poster.startLogin(handle);
        });
    }

    // Handle enter key on login input
    const handleInput = document.getElementById('poster-handle');
    if (handleInput) {
        handleInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                const handle = handleInput.value.trim();
                if (handle) Poster.startLogin(handle);
            }
        });
    }

    // Logout
    const logoutBtn = document.getElementById('poster-logout-btn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', () => {
            Poster.logout();
            document.getElementById('poster-login').style.display = 'block';
            document.getElementById('poster-session').style.display = 'none';
            document.getElementById('poster-result').innerHTML = '';
        });
    }

    // Test session
    const testBtn = document.getElementById('poster-test-btn');
    if (testBtn) {
        testBtn.addEventListener('click', async () => {
            showPosterResult('Testing session...', false);
            try {
                const data = await Poster.testSession();
                showPosterResult('<pre class="code-block">' + escapeHtml(JSON.stringify(data, null, 2)) + '</pre>', false);
            } catch (err) {
                showPosterResult('Error: ' + escapeHtml(err.message), true);
            }
        });
    }

    // Post button
    const postBtn = document.getElementById('poster-post-btn');
    if (postBtn) {
        postBtn.addEventListener('click', async () => {
            const text = document.getElementById('poster-text').value;
            if (!text.trim()) return;
            postBtn.disabled = true;
            showPosterResult('Posting...', false);
            try {
                const data = await Poster.createPost(text);
                showPosterResult('Posted! URI: <code>' + escapeHtml(data.uri) + '</code>', false);
                document.getElementById('poster-text').value = '';
                document.getElementById('poster-charcount').textContent = '0';
            } catch (err) {
                showPosterResult('Error: ' + escapeHtml(err.message), true);
            }
            postBtn.disabled = false;
        });
    }

    // Char counter
    const textarea = document.getElementById('poster-text');
    if (textarea) {
        textarea.addEventListener('input', () => {
            document.getElementById('poster-charcount').textContent = textarea.value.length;
        });
    }
}

function showPosterSession(did) {
    document.getElementById('poster-login').style.display = 'none';
    document.getElementById('poster-session').style.display = 'block';
    document.getElementById('poster-did').textContent = did;
}

function showPosterResult(html, isError) {
    const el = document.getElementById('poster-result');
    if (isError) {
        el.innerHTML = '<div style="color: var(--error-color); border: 1px solid var(--error-color); padding: 6px; background: #fff;">' + html + '</div>';
    } else {
        el.innerHTML = '<div style="padding: 6px; border: 1px solid #999; background: #fff;">' + html + '</div>';
    }
}


function escapeHtml(str) {
    if (!str) return '';
    if (typeof str !== 'string') {
        str = JSON.stringify(str);
    }
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}


let zCounter = 100;

function makeDraggable(win) {
    const titleBar = win.querySelector('.title-bar');
    if (!titleBar) return;

    titleBar.onmousedown = function (e) {
        if (e.target.tagName === 'BUTTON') return;

        win.style.zIndex = ++zCounter;

        const parentRect = win.offsetParent ? win.offsetParent.getBoundingClientRect() : { left: 0, top: 0 };
        const startLeft = win.offsetLeft;
        const startTop = win.offsetTop;
        const startX = e.clientX;
        const startY = e.clientY;

        document.onmousemove = function (e) {
            let newLeft = startLeft + (e.clientX - startX);
            let newTop = startTop + (e.clientY - startY);

            const maxLeft = (win.offsetParent ? win.offsetParent.clientWidth : window.innerWidth) - 50;
            const maxTop = (win.offsetParent ? win.offsetParent.clientHeight : window.innerHeight) - 50;
            newLeft = Math.max(-win.offsetWidth + 50, Math.min(newLeft, maxLeft));
            newTop = Math.max(0, Math.min(newTop, maxTop));

            win.style.left = newLeft + 'px';
            win.style.top = newTop + 'px';
        };

        document.onmouseup = function () {
            document.onmousemove = null;
            document.onmouseup = null;
        };
    };

    titleBar.ondragstart = function () {
        return false;
    };
}
