import { API } from './api.js';
import { CIDDecoder } from './cid.js';
import { renderDidDocument, renderDidSummary } from './did.js';
import { renderPlcOperations } from './plc.js';
import * as Poster from './poster.js';
import { MSTViewer } from './mst-viewer.js';
// Admin panel modules — loaded lazily since the admin-ui route may not be available
let AdminPanel, AdminOverview, AdminAccounts, AdminReports, AdminSystem;
async function loadAdminModules() {
    if (AdminPanel) return true;
    try {
        [AdminPanel, AdminOverview, AdminAccounts, AdminReports, AdminSystem] = (await Promise.all([
            import('/admin-ui/js/admin-panel.js'),
            import('/admin-ui/js/admin-overview.js'),
            import('/admin-ui/js/admin-accounts.js'),
            import('/admin-ui/js/admin-reports.js'),
            import('/admin-ui/js/admin-system.js'),
        ])).map(m => m.AdminPanel || m.AdminOverview || m.AdminAccounts || m.AdminReports || m.AdminSystem || m.default);
        return true;
    } catch (e) {
        console.warn('Admin panel modules not available:', e.message);
        return false;
    }
}

// Derive PLC base URL from current page origin
const PLC_BASE = (function() {
    const loc = window.location;
    const host = loc.hostname;
    if (host.endsWith('garazyk.xyz')) {
        return loc.protocol + '//plc.garazyk.xyz';
    }
    // For exe.dev proxy or other hosts, PLC is on port 4000
    return loc.protocol + '//' + host + ':4000';
})();

console.log('ui.js loading...');

const StateManager = {
    state: {
        currentDid: null,
        currentHandle: null,
        currentCollection: null,
        session: null,
        isAdmin: false
    },
    listeners: [],
    
    get(key) {
        return key ? this.state[key] : { ...this.state };
    },
    
    set(updates) {
        const prev = this.state;
        this.state = { ...this.state, ...updates };
        this.listeners.forEach(fn => fn(this.state, prev));
    },
    
    subscribe(listener) {
        this.listeners.push(listener);
        return () => {
            this.listeners = this.listeners.filter(fn => fn !== listener);
        };
    },
    
    reset() {
        this.state = { currentDid: null, currentHandle: null, currentCollection: null, session: null, isAdmin: false };
    }
};

let currentDid = null;
let currentHandle = null;
let currentCollection = null;

window.viewCollection = (collection) => {
    console.log('window.viewCollection called for collection:', collection);
    currentCollection = collection;
    StateManager.set({ currentCollection: collection });
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

    // MST Viewer
    MSTViewer.init();

    // Event delegation for dynamic buttons
    document.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-action]');
        if (!btn) return;
        e.preventDefault();
        const action = btn.dataset.action;
        if (action === 'view-collection') {
            window.viewCollection(btn.dataset.collection);
        } else if (action === 'view-record') {
            window.viewRecordDetail(btn.dataset.uri);
        } else if (action === 'open-window') {
            window.openWindow(btn.dataset.window);
        } else if (action === 'close-window') {
            window.closeWindow(btn.dataset.window);
        }
    });

    // Session management (OAuth, login/logout, poster)
    initSession();

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
                <span style="font-size:14px">◉</span>
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
    
    StateManager.set({ currentDid: account.did, currentHandle: account.handle || '' });

    MSTViewer.setDID(account.did);

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
    StateManager.set({ currentDid: result.did });

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

    try {
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
    } catch (error) {
        console.error('showDidDocument failed:', error);
        ErrorBoundary.showError('did-content', error.message, () => showDidDocument(did));
        ErrorBoundary.showError('plc-content', error.message, () => showDidDocument(did));
        ErrorBoundary.showError('collections-content', error.message, () => showDidDocument(did));
    }
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
                <td><button class="btn-secondary" data-action="view-collection" data-collection="${escapeHtml(collection)}">View Records</button></td>
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
                <td><button class="btn-secondary" data-action="view-record" data-uri="${escapeHtml(record.uri)}">View Detail</button></td>
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
    const container = document.getElementById('record-content');
    container.className = 'code-block';
    container.style.whiteSpace = 'pre-wrap';
    container.style.wordBreak = 'break-all';
    container.innerHTML = '';
    container.textContent = 'Loading...';

    try {
        const record = await API.getRecord(uri);
        console.log('getRecord result:', record);
        if (record.error) {
            container.textContent = record.error;
            return;
        }

        const recordType = record.value?.$type || record.$type || '';
        if (recordType === 'app.bsky.feed.post') {
            renderPostWithToggle(container, record);
        } else if (recordType === 'app.bsky.actor.profile') {
            renderGenericWithToggle(container, record, renderProfileClassic(record.value || record));
        } else if (recordType === 'app.bsky.feed.like') {
            renderGenericWithToggle(container, record, renderLikeClassic(record.value || record));
        } else if (recordType === 'app.bsky.graph.follow') {
            renderGenericWithToggle(container, record, renderFollowClassic(record.value || record));
        } else {
            container.textContent = JSON.stringify(record, null, 2);
        }
    } catch (e) {
        console.error('Failed to get record:', e);
        container.textContent = 'Error: ' + e.message;
    }
}

function renderPostWithToggle(container, record) {
    const postData = record.value || record;
    const jsonStr = JSON.stringify(record, null, 2);

    // Switch to a plain div for rich content
    container.className = '';
    container.style.whiteSpace = '';
    container.style.wordBreak = '';
    container.innerHTML = '';

    // Toggle bar
    const toggleBar = document.createElement('div');
    toggleBar.style.cssText = 'margin-bottom: 8px; display: flex; gap: 4px;';

    const btnRendered = document.createElement('button');
    btnRendered.className = 'btn btn-default';
    btnRendered.textContent = 'Rendered';
    btnRendered.style.cssText = 'font-family: Chicago_12, monospace; font-size: 12px;';

    const btnJSON = document.createElement('button');
    btnJSON.className = 'btn';
    btnJSON.textContent = 'JSON';
    btnJSON.style.cssText = 'font-family: Chicago_12, monospace; font-size: 12px;';

    toggleBar.appendChild(btnRendered);
    toggleBar.appendChild(btnJSON);
    container.appendChild(toggleBar);

    // Rendered view
    const renderedView = document.createElement('div');
    renderedView.innerHTML = renderPostClassic(postData);
    container.appendChild(renderedView);

    // JSON view
    const jsonView = document.createElement('pre');
    jsonView.className = 'code-block';
    jsonView.textContent = jsonStr;
    jsonView.style.display = 'none';
    container.appendChild(jsonView);

    btnRendered.addEventListener('click', () => {
        renderedView.style.display = '';
        jsonView.style.display = 'none';
        btnRendered.className = 'btn btn-default';
        btnJSON.className = 'btn';
    });

    btnJSON.addEventListener('click', () => {
        renderedView.style.display = 'none';
        jsonView.style.display = '';
        btnJSON.className = 'btn btn-default';
        btnRendered.className = 'btn';
    });
}

function renderGenericWithToggle(container, record, renderedHtml) {
    const jsonStr = JSON.stringify(record, null, 2);
    container.className = '';
    container.style.whiteSpace = '';
    container.style.wordBreak = '';
    container.innerHTML = '';

    const toggleBar = document.createElement('div');
    toggleBar.style.cssText = 'margin-bottom: 8px; display: flex; gap: 4px;';

    const btnRendered = document.createElement('button');
    btnRendered.className = 'btn btn-default';
    btnRendered.textContent = 'Rendered';
    btnRendered.style.cssText = 'font-family: Chicago_12, monospace; font-size: 12px;';

    const btnJSON = document.createElement('button');
    btnJSON.className = 'btn';
    btnJSON.textContent = 'JSON';
    btnJSON.style.cssText = 'font-family: Chicago_12, monospace; font-size: 12px;';

    toggleBar.appendChild(btnRendered);
    toggleBar.appendChild(btnJSON);
    container.appendChild(toggleBar);

    const renderedView = document.createElement('div');
    renderedView.innerHTML = renderedHtml;
    container.appendChild(renderedView);

    const jsonView = document.createElement('pre');
    jsonView.className = 'code-block';
    jsonView.textContent = jsonStr;
    jsonView.style.display = 'none';
    container.appendChild(jsonView);

    btnRendered.addEventListener('click', () => {
        renderedView.style.display = '';
        jsonView.style.display = 'none';
        btnRendered.className = 'btn btn-default';
        btnJSON.className = 'btn';
    });

    btnJSON.addEventListener('click', () => {
        renderedView.style.display = 'none';
        jsonView.style.display = '';
        btnJSON.className = 'btn btn-default';
        btnRendered.className = 'btn';
    });
}

function renderRichText(text, facets) {
    if (!facets || facets.length === 0) {
        return escapeHtml(text).replace(/\n/g, '<br>');
    }

    // Convert text to byte array for proper indexing
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const bytes = encoder.encode(text);

    // Sort facets by byteStart
    const sorted = [...facets].sort((a, b) => {
        const aStart = a.index?.byteStart ?? 0;
        const bStart = b.index?.byteStart ?? 0;
        return aStart - bStart;
    });

    let html = '';
    let lastEnd = 0;

    for (const facet of sorted) {
        const start = facet.index?.byteStart ?? 0;
        const end = facet.index?.byteEnd ?? 0;
        if (start < lastEnd || end > bytes.length) continue;

        // Plain text before this facet
        if (start > lastEnd) {
            html += escapeHtml(decoder.decode(bytes.slice(lastEnd, start))).replace(/\n/g, '<br>');
        }

        const facetText = escapeHtml(decoder.decode(bytes.slice(start, end)));
        const feature = facet.features?.[0];

        if (feature?.$type === 'app.bsky.richtext.facet#link') {
            html += '<a href="' + escapeHtml(feature.uri) + '" target="_blank" class="rt-link">' + facetText + '</a>';
        } else if (feature?.$type === 'app.bsky.richtext.facet#mention') {
            html += '<span class="rt-mention" title="' + escapeHtml(feature.did || '') + '">@' + facetText.replace(/^@/, '') + '</span>';
        } else if (feature?.$type === 'app.bsky.richtext.facet#tag') {
            html += '<span class="rt-tag">#' + facetText.replace(/^#/, '') + '</span>';
        } else {
            html += facetText;
        }

        lastEnd = end;
    }

    // Remaining text
    if (lastEnd < bytes.length) {
        html += escapeHtml(decoder.decode(bytes.slice(lastEnd))).replace(/\n/g, '<br>');
    }

    return html;
}

function renderPostClassic(postData) {
    const text = escapeHtml(postData.text || '');
    const createdAt = postData.createdAt || '';
    const langs = (postData.langs || []).map(l => escapeHtml(l)).join(', ');

    let dateStr = '';
    if (createdAt) {
        try {
            const d = new Date(createdAt);
            dateStr = d.toLocaleDateString('en-US', { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' })
                + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
        } catch (_) {
            dateStr = escapeHtml(createdAt);
        }
    }

    let html = '<div class="post-classic">';

    // Header
    html += '<div class="post-classic-header">';
    html += '<span class="post-classic-icon">¶</span>';
    html += '<span class="post-classic-type">app.bsky.feed.post</span>';
    if (dateStr) {
        html += '<span class="post-classic-date">' + dateStr + '</span>';
    }
    html += '</div>';

    // Body
    html += '<div class="post-classic-body">';
    const richHtml = renderRichText(postData.text || '', postData.facets);
    html += '<div class="post-classic-text">' + richHtml + '</div>';
    html += '</div>';

    // Reply info
    if (postData.reply) {
        html += '<div class="post-classic-meta">';
        html += '<span class="post-classic-meta-label">↩ Reply to:</span> ';
        html += '<code class="post-classic-meta-value">' + escapeHtml(postData.reply.parent?.uri || 'unknown') + '</code>';
        html += '</div>';
    }

    // Embeds
    if (postData.embed) {
        html += '<div class="post-classic-embed">';
        html += renderEmbedClassic(postData.embed);
        html += '</div>';
    }

    // Facets (note: already rendered in rich text above)
    if (postData.facets && postData.facets.length > 0) {
        html += '<div class="post-classic-meta">';
        html += '<span class="post-classic-meta-label">Facets:</span> ';
        html += escapeHtml(postData.facets.length + ' rich-text annotation(s)');
        html += '</div>';
    }

    // Languages
    if (langs) {
        html += '<div class="post-classic-meta">';
        html += '<span class="post-classic-meta-label">Lang:</span> ';
        html += '<span class="post-classic-meta-value">' + langs + '</span>';
        html += '</div>';
    }

    html += '</div>';
    return html;
}

function renderEmbedClassic(embed) {
    const type = embed.$type || '';
    let html = '<div class="post-classic-embed-inner">';

    if (type === 'app.bsky.embed.images') {
        const images = embed.images || [];
        html += '<span class="post-classic-meta-label">▣ ' + images.length + ' image(s)</span>';
        for (const img of images) {
            if (img.alt) {
                html += '<div class="post-classic-embed-alt">Alt: ' + escapeHtml(img.alt) + '</div>';
            }
        }
    } else if (type === 'app.bsky.embed.external') {
        const ext = embed.external || {};
        html += '<span class="post-classic-meta-label">⌘ External link</span>';
        if (ext.title) html += '<div style="font-weight: bold; margin-top: 4px;">' + escapeHtml(ext.title) + '</div>';
        if (ext.uri) html += '<div><code>' + escapeHtml(ext.uri) + '</code></div>';
        if (ext.description) html += '<div style="color: #666; margin-top: 2px;">' + escapeHtml(ext.description) + '</div>';
    } else if (type === 'app.bsky.embed.record') {
        html += '<span class="post-classic-meta-label">⊞ Quoted record</span>';
        if (embed.record?.uri) html += '<div><code>' + escapeHtml(embed.record.uri) + '</code></div>';
    } else if (type === 'app.bsky.embed.recordWithMedia') {
        html += '<span class="post-classic-meta-label">⊞ Record + Media</span>';
        if (embed.record?.record?.uri) html += '<div><code>' + escapeHtml(embed.record.record.uri) + '</code></div>';
    } else {
        html += '<span class="post-classic-meta-label">Embed: ' + escapeHtml(type) + '</span>';
    }

    html += '</div>';
    return html;
}

function renderProfileClassic(profileData) {
    const displayName = escapeHtml(profileData.displayName || '');
    const description = escapeHtml(profileData.description || '');
    const createdAt = profileData.createdAt || '';

    let dateStr = '';
    if (createdAt) {
        try {
            const d = new Date(createdAt);
            dateStr = d.toLocaleDateString('en-US', { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' });
        } catch (_) {
            dateStr = escapeHtml(createdAt);
        }
    }

    let html = '<div class="classic-card">';
    html += '<div class="classic-card-header">';
    html += '<span class="post-classic-icon">☰</span>';
    html += '<span class="post-classic-type">app.bsky.actor.profile</span>';
    if (dateStr) {
        html += '<span class="post-classic-date">' + dateStr + '</span>';
    }
    html += '</div>';

    html += '<div class="classic-card-body">';
    if (displayName) {
        html += '<div class="profile-classic-name">' + displayName + '</div>';
    }
    if (description) {
        html += '<div class="profile-classic-bio">' + description.replace(/\n/g, '<br>') + '</div>';
    }

    // Avatar/Banner refs
    if (profileData.avatar) {
        html += '<div class="post-classic-meta" style="border-top: none;">';
        html += '<span class="post-classic-meta-label">▣ Avatar:</span> ';
        html += '<code class="post-classic-meta-value">' + escapeHtml(profileData.avatar?.ref?.$link || 'blob') + '</code>';
        html += '</div>';
    }
    if (profileData.banner) {
        html += '<div class="post-classic-meta" style="border-top: none;">';
        html += '<span class="post-classic-meta-label">▤ Banner:</span> ';
        html += '<code class="post-classic-meta-value">' + escapeHtml(profileData.banner?.ref?.$link || 'blob') + '</code>';
        html += '</div>';
    }

    html += '</div>';
    html += '</div>';
    return html;
}

function renderLikeClassic(likeData) {
    const createdAt = likeData.createdAt || '';
    const subjectUri = escapeHtml(likeData.subject?.uri || '');
    const subjectCid = escapeHtml(likeData.subject?.cid || '');

    let dateStr = '';
    if (createdAt) {
        try {
            const d = new Date(createdAt);
            dateStr = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
                + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
        } catch (_) {
            dateStr = escapeHtml(createdAt);
        }
    }

    let html = '<div class="classic-card">';
    html += '<div class="classic-card-header">';
    html += '<span class="post-classic-icon">♡</span>';
    html += '<span class="post-classic-type">app.bsky.feed.like</span>';
    if (dateStr) {
        html += '<span class="post-classic-date">' + dateStr + '</span>';
    }
    html += '</div>';
    html += '<div class="classic-card-body">';
    html += '<div class="post-classic-meta" style="border: none; padding: 0;">';
    html += '<span class="post-classic-meta-label">Subject:</span> ';
    html += '<code class="post-classic-meta-value">' + subjectUri + '</code>';
    html += '</div>';
    if (subjectCid) {
        html += '<div class="post-classic-meta" style="border: none; padding: 2px 0 0;">';
        html += '<span class="post-classic-meta-label">CID:</span> ';
        html += '<code class="post-classic-meta-value">' + subjectCid.slice(0, 16) + '…</code>';
        html += '</div>';
    }
    html += '</div>';
    html += '</div>';
    return html;
}

function renderFollowClassic(followData) {
    const createdAt = followData.createdAt || '';
    const subject = escapeHtml(followData.subject || '');

    let dateStr = '';
    if (createdAt) {
        try {
            const d = new Date(createdAt);
            dateStr = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
                + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
        } catch (_) {
            dateStr = escapeHtml(createdAt);
        }
    }

    let html = '<div class="classic-card">';
    html += '<div class="classic-card-header">';
    html += '<span class="post-classic-icon">⇄</span>';
    html += '<span class="post-classic-type">app.bsky.graph.follow</span>';
    if (dateStr) {
        html += '<span class="post-classic-date">' + dateStr + '</span>';
    }
    html += '</div>';
    html += '<div class="classic-card-body">';
    html += '<div class="post-classic-meta" style="border: none; padding: 0;">';
    html += '<span class="post-classic-meta-label">Following:</span> ';
    html += '<code class="post-classic-meta-value">' + subject + '</code>';
    html += '</div>';
    html += '</div>';
    html += '</div>';
    return html;
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
    for (let i = 0; i < result.posts.length; i++) {
        const post = result.posts[i];
        const postData = post.record || {};
        const text = escapeHtml(postData.text || '');
        const handle = escapeHtml(post.author?.handle || post.author?.did || '');
        const jsonStr = escapeHtml(JSON.stringify(post, null, 2));

        let dateStr = '';
        if (postData.createdAt) {
            try {
                const d = new Date(postData.createdAt);
                dateStr = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
                    + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
            } catch (_) {
                dateStr = escapeHtml(postData.createdAt);
            }
        }

        html += '<div class="post-classic">';

        // Header with toggle
        html += '<div class="post-classic-header">';
        html += '<span class="post-classic-icon">◉</span>';
        html += '<span class="post-classic-type">' + handle + '</span>';
        if (dateStr) {
            html += '<span class="post-classic-date">' + dateStr + '</span>';
        }
        html += '<button class="btn post-classic-toggle" data-toggle-post="' + i + '">JSON</button>';
        html += '</div>';

        // Rendered body
        html += '<div class="post-classic-body" id="post-rendered-' + i + '">';
        html += '<div class="post-classic-text">' + text.replace(/\n/g, '<br>') + '</div>';

        if (postData.reply) {
            html += '<div class="post-classic-meta" style="margin-top: 6px;">';
            html += '<span class="post-classic-meta-label">↩ Reply to:</span> ';
            html += '<code class="post-classic-meta-value">' + escapeHtml(postData.reply.parent?.uri || 'unknown') + '</code>';
            html += '</div>';
        }

        if (postData.embed) {
            html += '<div class="post-classic-embed">';
            html += renderEmbedClassic(postData.embed);
            html += '</div>';
        }

        html += '</div>';

        // JSON body (hidden)
        html += '<pre class="code-block" id="post-json-' + i + '" style="display: none; margin: 0;">' + jsonStr + '</pre>';

        html += '</div>';
    }

    content.innerHTML = html;

    // Attach toggle handlers
    content.querySelectorAll('[data-toggle-post]').forEach(btn => {
        btn.addEventListener('click', () => {
            const idx = btn.dataset.togglePost;
            const rendered = document.getElementById('post-rendered-' + idx);
            const json = document.getElementById('post-json-' + idx);
            if (json.style.display === 'none') {
                json.style.display = '';
                rendered.style.display = 'none';
                btn.textContent = 'Rendered';
            } else {
                json.style.display = 'none';
                rendered.style.display = '';
                btn.textContent = 'JSON';
            }
        });
    });
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
    for (let i = 0; i < result.likes.length; i++) {
        const like = result.likes[i];
        const subjectUri = escapeHtml(like.subject?.uri || '');
        const createdAt = like.createdAt || '';
        const jsonStr = escapeHtml(JSON.stringify(like, null, 2));

        let dateStr = '';
        if (createdAt) {
            try {
                const d = new Date(createdAt);
                dateStr = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
                    + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
            } catch (_) {
                dateStr = escapeHtml(createdAt);
            }
        }

        html += '<div class="classic-card">';
        html += '<div class="classic-card-header">';
        html += '<span class="post-classic-icon">♡</span>';
        html += '<span class="post-classic-type">Like</span>';
        if (dateStr) {
            html += '<span class="post-classic-date">' + dateStr + '</span>';
        }
        html += '<button class="btn post-classic-toggle" data-toggle-like="' + i + '">JSON</button>';
        html += '</div>';

        html += '<div class="classic-card-body" id="like-rendered-' + i + '">';
        html += '<div class="post-classic-meta" style="border: none; padding: 0;">';
        html += '<span class="post-classic-meta-label">Subject:</span> ';
        html += '<code class="post-classic-meta-value">' + subjectUri + '</code>';
        html += '</div>';
        html += '</div>';

        html += '<pre class="code-block" id="like-json-' + i + '" style="display: none; margin: 0;">' + jsonStr + '</pre>';
        html += '</div>';
    }

    content.innerHTML = html;

    content.querySelectorAll('[data-toggle-like]').forEach(btn => {
        btn.addEventListener('click', () => {
            const idx = btn.dataset.toggleLike;
            const rendered = document.getElementById('like-rendered-' + idx);
            const json = document.getElementById('like-json-' + idx);
            if (json.style.display === 'none') {
                json.style.display = '';
                rendered.style.display = 'none';
                btn.textContent = 'Rendered';
            } else {
                json.style.display = 'none';
                rendered.style.display = '';
                btn.textContent = 'JSON';
            }
        });
    });
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
    for (let i = 0; i < result.actors.length; i++) {
        const actor = result.actors[i];
        const handle = escapeHtml(actor.handle || '');
        const did = escapeHtml(actor.did || '');
        const displayName = escapeHtml(actor.displayName || '');
        const jsonStr = escapeHtml(JSON.stringify(actor, null, 2));

        html += '<div class="classic-card">';
        html += '<div class="classic-card-header">';
        html += '<span class="post-classic-icon">◉</span>';
        html += '<span class="post-classic-type">' + handle + '</span>';
        html += '<button class="btn post-classic-toggle" data-toggle-follow="' + i + '">JSON</button>';
        html += '</div>';

        html += '<div class="classic-card-body" id="follow-rendered-' + i + '">';
        if (displayName) {
            html += '<div class="profile-classic-name" style="font-size: 12px;">' + displayName + '</div>';
        }
        html += '<div class="post-classic-meta" style="border: none; padding: 2px 0 0;">';
        html += '<span class="post-classic-meta-label">DID:</span> ';
        html += '<code class="post-classic-meta-value">' + did + '</code>';
        html += '</div>';
        html += '</div>';

        html += '<pre class="code-block" id="follow-json-' + i + '" style="display: none; margin: 0;">' + jsonStr + '</pre>';
        html += '</div>';
    }

    content.innerHTML = html;

    content.querySelectorAll('[data-toggle-follow]').forEach(btn => {
        btn.addEventListener('click', () => {
            const idx = btn.dataset.toggleFollow;
            const rendered = document.getElementById('follow-rendered-' + idx);
            const json = document.getElementById('follow-json-' + idx);
            if (json.style.display === 'none') {
                json.style.display = '';
                rendered.style.display = 'none';
                btn.textContent = 'Rendered';
            } else {
                json.style.display = 'none';
                rendered.style.display = '';
                btn.textContent = 'JSON';
            }
        });
    });
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

    const jsonStr = JSON.stringify(result, null, 2);

    let dateStr = '';
    if (result.createdAt) {
        try {
            const d = new Date(result.createdAt);
            dateStr = d.toLocaleDateString('en-US', { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' });
        } catch (_) {
            dateStr = escapeHtml(result.createdAt);
        }
    }

    // Toggle bar
    let html = '<div style="margin-bottom: 8px; display: flex; gap: 4px;">';
    html += '<button class="btn btn-default" id="profile-btn-rendered" style="font-family: Chicago_12, monospace; font-size: 12px;">Rendered</button>';
    html += '<button class="btn" id="profile-btn-json" style="font-family: Chicago_12, monospace; font-size: 12px;">JSON</button>';
    html += '</div>';

    // Rendered view
    html += '<div id="profile-rendered-view">';
    html += '<div class="classic-card">';
    html += '<div class="classic-card-header">';
    html += '<span class="post-classic-icon">☰</span>';
    html += '<span class="post-classic-type">' + escapeHtml(result.handle || 'Profile') + '</span>';
    if (dateStr) {
        html += '<span class="post-classic-date">Joined ' + dateStr + '</span>';
    }
    html += '</div>';

    html += '<div class="classic-card-body">';
    html += '<div class="profile-classic-name">' + escapeHtml(result.displayName || result.handle) + '</div>';
    html += '<div style="color:#666; font-size: 11px; margin-bottom: 6px;">@' + escapeHtml(result.handle) + ' · <code style="font-size: 10px;">' + escapeHtml(result.did) + '</code></div>';

    if (result.description) {
        html += '<div class="profile-classic-bio">' + escapeHtml(result.description).replace(/\n/g, '<br>') + '</div>';
    }

    html += '<div class="profile-classic-stats">';
    html += '<div class="profile-classic-stat"><strong>' + (result.postsCount || 0) + '</strong> posts</div>';
    html += '<div class="profile-classic-stat"><strong>' + (result.followsCount || 0) + '</strong> following</div>';
    html += '<div class="profile-classic-stat"><strong>' + (result.followersCount || 0) + '</strong> followers</div>';
    html += '</div>';

    html += '</div>';
    html += '</div>';
    html += '</div>';

    // JSON view (hidden)
    html += '<pre class="code-block" id="profile-json-view" style="display: none;">' + escapeHtml(jsonStr) + '</pre>';

    content.innerHTML = html;

    // Toggle handlers
    const btnRendered = document.getElementById('profile-btn-rendered');
    const btnJSON = document.getElementById('profile-btn-json');
    const renderedView = document.getElementById('profile-rendered-view');
    const jsonView = document.getElementById('profile-json-view');

    btnRendered.addEventListener('click', () => {
        renderedView.style.display = '';
        jsonView.style.display = 'none';
        btnRendered.className = 'btn btn-default';
        btnJSON.className = 'btn';
    });

    btnJSON.addEventListener('click', () => {
        renderedView.style.display = 'none';
        jsonView.style.display = '';
        btnJSON.className = 'btn btn-default';
        btnRendered.className = 'btn';
    });
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


// --- Session Management ---

let sessionIsAdmin = false;

function initSession() {
    // Check for OAuth callback on page load
    Poster.handleOAuthCallback().then(result => {
        if (result && !result.error && result.did) {
            // Store handle if available (from sessionStorage set during login)
            const handle = sessionStorage.getItem('login_handle') || result.did;
            fetchSessionAndCheckAdmin(result.did, handle);
            showPosterResult('Logged in successfully!', false);
        } else if (result && result.error) {
            showPosterResult('Error: ' + result.error, true);
        }
    });

    // Restore session if exists
    const session = Poster.getSession();
    if (session) {
        const handle = sessionStorage.getItem('login_handle') || session.did;
        fetchSessionAndCheckAdmin(session.did, handle);
    }

    // --- File Menu: Login ---
    const menuLogin = document.getElementById('menu-login');
    if (menuLogin) {
        menuLogin.addEventListener('click', (e) => {
            e.preventDefault();
            document.getElementById('win-login').style.display = 'block';
            document.getElementById('login-handle').focus();
        });
    }

    // Login dialog: Login button
    const loginBtn = document.getElementById('login-btn');
    if (loginBtn) {
        loginBtn.addEventListener('click', () => {
            const handle = document.getElementById('login-handle').value.trim();
            if (!handle) return;
            triggerLogin(handle);
        });
    }

    // Login dialog: Enter key
    const loginHandleInput = document.getElementById('login-handle');
    if (loginHandleInput) {
        loginHandleInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                const handle = loginHandleInput.value.trim();
                if (!handle) return;
                triggerLogin(handle);
            }
        });

        // Resolve on blur
        loginHandleInput.addEventListener('blur', async () => {
            const handle = loginHandleInput.value.trim();
            if (!handle || !handle.includes('.')) return;
            const statusEl = document.getElementById('login-resolve-status');
            statusEl.textContent = 'Resolving…';
            const did = await Poster.resolveHandle(handle);
            if (did) {
                statusEl.innerHTML = '✅ Resolved: <code>' + escapeHtml(did) + '</code>';
            } else {
                statusEl.textContent = '❌ Could not resolve handle';
            }
        });
    }

    // --- File Menu: Logout ---
    const menuLogout = document.getElementById('menu-logout');
    if (menuLogout) {
        menuLogout.addEventListener('click', (e) => {
            e.preventDefault();
            Poster.logout();
            sessionStorage.removeItem('login_handle');
            updateUIForLogout();
        });
    }

    // --- File Menu: New Post ---
    const menuPoster = document.getElementById('menu-poster');
    if (menuPoster) {
        menuPoster.addEventListener('click', async (e) => {
            e.preventDefault();
            const handle = sessionStorage.getItem('login_handle') || '';
            document.getElementById('poster-handle').textContent = handle;
            document.getElementById('win-poster').style.display = 'block';
            // Load recent posts
            const recentList = document.getElementById('poster-recent-list');
            if (recentList) {
                recentList.innerHTML = '<p style="color: #999; margin: 0;">Loading...</p>';
                const posts = await Poster.loadRecentPosts();
                if (posts.length === 0) {
                    recentList.innerHTML = '<p style="color: #999; margin: 0;">No posts yet.</p>';
                } else {
                    recentList.innerHTML = posts.map(p => {
                        const text = p.value?.text || '';
                        const date = p.value?.createdAt || '';
                        const shortDate = date ? new Date(date).toLocaleString() : '';
                        return '<div style="border-bottom: 1px solid #ddd; padding: 4px 0; font-size: 11px;">'
                            + '<div style="white-space: pre-wrap;">' + escapeHtml(text) + '</div>'
                            + '<div style="color: #999; font-size: 10px;">' + escapeHtml(shortDate) + '</div>'
                            + '</div>';
                    }).join('');
                }
            }
        });
    }

    // Poster: Test session button
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

    // Poster: Post button
    const postBtn = document.getElementById('poster-post-btn');
    if (postBtn) {
        postBtn.addEventListener('click', async () => {
            const text = document.getElementById('poster-text').value;
            if (!text.trim()) return;
            const replyTo = document.getElementById('poster-reply-to')?.value.trim() || '';
            postBtn.disabled = true;
            showPosterResult('Posting...', false);
            try {
                const data = await Poster.createPost(text, replyTo || undefined);
                showPosterResult('Posted! URI: <code>' + escapeHtml(data.uri) + '</code>', false);
                document.getElementById('poster-text').value = '';
                document.getElementById('poster-charcount').textContent = '0';
                if (document.getElementById('poster-reply-to')) document.getElementById('poster-reply-to').value = '';
            } catch (err) {
                showPosterResult('Error: ' + escapeHtml(err.message) + ' <button class="btn" id="poster-retry-btn" style="margin-left: 8px;">Retry</button>', true);
                const retryBtn = document.getElementById('poster-retry-btn');
                if (retryBtn) {
                    retryBtn.addEventListener('click', () => postBtn.click());
                }
            }
            postBtn.disabled = false;
        });
    }

    // Poster: Char counter
    const textarea = document.getElementById('poster-text');
    if (textarea) {
        textarea.addEventListener('input', () => {
            let count;
            if (typeof Intl !== 'undefined' && Intl.Segmenter) {
                const segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' });
                count = [...segmenter.segment(textarea.value)].length;
            } else {
                count = textarea.value.length;
            }
            const el = document.getElementById('poster-charcount');
            el.textContent = count;
            el.style.color = count > 300 ? '#ff0000' : '#666';
        });
    }

    // --- Admin Menu: Invite Codes ---
    const menuInviteCodes = document.getElementById('menu-invite-codes');
    if (menuInviteCodes) {
        menuInviteCodes.addEventListener('click', (e) => {
            e.preventDefault();
            openAdminPanel('system');
        });
    }

    // --- Admin Menu: Moderation ---
    const menuModeration = document.getElementById('menu-moderation');
    if (menuModeration) {
        menuModeration.addEventListener('click', (e) => {
            e.preventDefault();
            openAdminPanel('reports');
        });
    }

    // --- Admin Login button ---
    const adminLoginBtn = document.getElementById('admin-login-btn');
    if (adminLoginBtn) {
        adminLoginBtn.addEventListener('click', () => AdminAPI.doLogin());
    }

    const adminPasswordInput = document.getElementById('admin-password');
    if (adminPasswordInput) {
        adminPasswordInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') AdminAPI.doLogin();
        });
    }

    // --- Invite Generate button ---
    const inviteGenBtn = document.getElementById('invite-generate-btn');
    if (inviteGenBtn) {
        inviteGenBtn.addEventListener('click', () => AdminAPI.generateInviteCode());
    }

    // --- Admin Panel Tab Initialization ---
    initAdminPanelTabs();
}

async function openAdminPanel(tab = 'overview') {
    const loaded = await loadAdminModules();
    if (!loaded) {
        alert('Admin panel modules are not available.');
        return;
    }
    if (!AdminPanel.isAuthenticated()) {
        AdminAPI.promptLogin(() => {
            AdminPanel.setToken(sessionStorage.getItem('admin_token'));
            showAdminPanel(tab);
        });
        return;
    }
    showAdminPanel(tab);
}

function showAdminPanel(tab) {
    const panel = document.getElementById('win-admin-panel');
    if (panel) {
        panel.style.display = 'block';
        AdminPanel.switchTab(tab);

        if (tab === 'overview') {
            AdminOverview.load();
        } else if (tab === 'accounts') {
            AdminAccounts.load();
        } else if (tab === 'reports') {
            AdminReports.load();
        } else if (tab === 'system') {
            AdminSystem.load();
        }
    }
}

function initAdminPanelTabs() {
    document.querySelectorAll('.admin-tab').forEach(tab => {
        tab.addEventListener('click', () => {
            const tabId = tab.dataset.tab;
            AdminPanel.switchTab(tabId);

            if (tabId === 'overview') {
                AdminOverview.load();
            } else if (tabId === 'accounts') {
                AdminAccounts.load();
            } else if (tabId === 'reports') {
                AdminReports.load();
            } else if (tabId === 'system') {
                AdminSystem.load();
            }
        });
    });

    const accountsSearch = document.getElementById('admin-accounts-search');
    if (accountsSearch) {
        accountsSearch.addEventListener('input', () => {
            AdminAccounts.search(accountsSearch.value);
        });
    }

    const reportsStatusFilter = document.getElementById('admin-reports-status-filter');
    if (reportsStatusFilter) {
        reportsStatusFilter.addEventListener('change', () => {
            AdminReports.setStatusFilter(reportsStatusFilter.value);
        });
    }
}

function triggerLogin(handle) {
    sessionStorage.setItem('login_handle', handle);
    document.getElementById('win-login').style.display = 'none';
    Poster.startLogin(handle);
}

// --- Admin API ---
const AdminAPI = {
    _token: null,
    _onLoginCallback: null,

    isAuthenticated() {
        return !!sessionStorage.getItem('admin_token');
    },

    getToken() {
        return sessionStorage.getItem('admin_token');
    },

    promptLogin(callback) {
        this._onLoginCallback = callback;
        document.getElementById('admin-login-error').textContent = '';
        document.getElementById('admin-password').value = '';
        document.getElementById('win-admin-login').style.display = 'block';
        document.getElementById('admin-password').focus();
    },

    async doLogin() {
        const password = document.getElementById('admin-password').value;
        if (!password) {
            document.getElementById('admin-login-error').textContent = 'Password required.';
            return;
        }

        try {
            const resp = await fetch('/admin/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password })
            });
            const data = await resp.json();
            if (resp.ok && data.token) {
                sessionStorage.setItem('admin_token', data.token);
                document.getElementById('win-admin-login').style.display = 'none';
                // Show admin menu group
                const adminGroup = document.getElementById('menu-admin-group');
                if (adminGroup) adminGroup.style.display = '';
                if (this._onLoginCallback) {
                    this._onLoginCallback();
                    this._onLoginCallback = null;
                }
            } else {
                document.getElementById('admin-login-error').textContent = data.error || 'Login failed.';
            }
        } catch (e) {
            document.getElementById('admin-login-error').textContent = 'Connection error.';
        }
    },

    async adminFetch(url, opts = {}) {
        const token = this.getToken();
        if (!token) throw new Error('Not admin-authenticated');
        const headers = { ...(opts.headers || {}), 'Authorization': 'Bearer ' + token };
        const resp = await fetch(url, { ...opts, headers });
        if (resp.status === 401) {
            sessionStorage.removeItem('admin_token');
            this.promptLogin(() => { });
            throw new Error('Admin session expired');
        }
        return resp;
    },

    async loadInviteCodes() {
        const tbody = document.getElementById('invite-table-body');
        const countEl = document.getElementById('invite-count');
        tbody.innerHTML = '<tr><td colspan="5" style="padding: 8px; text-align: center;">Loading...</td></tr>';

        try {
            const resp = await this.adminFetch('/admin/invites');
            const data = await resp.json();
            const invites = data.invites || [];
            countEl.textContent = invites.length + ' invite code(s)';

            if (invites.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" style="padding: 8px; text-align: center;">No invite codes</td></tr>';
                return;
            }

            tbody.innerHTML = '';
            for (const inv of invites) {
                const tr = document.createElement('tr');
                const disabled = inv.disabled;
                const status = disabled ? '🔴 Disabled' : '🟢 Active';
                tr.innerHTML = `
                    <td style="padding: 4px;"><code>${escapeHtml(inv.code)}</code></td>
                    <td style="padding: 4px;">${escapeHtml(inv.created_by)}</td>
                    <td style="padding: 4px; text-align: center;">${inv.uses || 0}/${inv.max_uses || 1}</td>
                    <td style="padding: 4px; text-align: center;">${status}</td>
                    <td style="padding: 4px; text-align: center;">${disabled ? '' : '<button class="btn" data-disable-code="' + escapeHtml(inv.code) + '">Disable</button>'}</td>
                `;
                tbody.appendChild(tr);
            }

            // Attach disable handlers
            tbody.querySelectorAll('[data-disable-code]').forEach(btn => {
                btn.addEventListener('click', async () => {
                    const code = btn.dataset.disableCode;
                    try {
                        await this.adminFetch('/admin/invites/disable', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ code })
                        });
                        this.loadInviteCodes();
                    } catch (e) {
                        document.getElementById('invite-result').innerHTML = '<div style="color: red;">' + escapeHtml(e.message) + '</div>';
                    }
                });
            });
        } catch (e) {
            tbody.innerHTML = '<tr><td colspan="5" style="padding: 8px; text-align: center; color: red;">Error: ' + escapeHtml(e.message) + '</td></tr>';
        }
    },

    async generateInviteCode() {
        const resultEl = document.getElementById('invite-result');
        try {
            const resp = await this.adminFetch('/xrpc/com.atproto.server.createInviteCode', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ useCount: 1 })
            });
            const data = await resp.json();
            if (data.code) {
                resultEl.innerHTML = '<div style="border: 1px solid #000; padding: 6px; background: #fff;">New code: <strong><code>' + escapeHtml(data.code) + '</code></strong></div>';
                this.loadInviteCodes();
            } else {
                resultEl.innerHTML = '<div style="color: red;">' + escapeHtml(data.error || 'Unknown error') + '</div>';
            }
        } catch (e) {
            resultEl.innerHTML = '<div style="color: red;">' + escapeHtml(e.message) + '</div>';
        }
    },

    async loadModeration() {
        const tbody = document.getElementById('moderation-table-body');
        const countEl = document.getElementById('moderation-count');
        tbody.innerHTML = '<tr><td colspan="5" style="padding: 8px; text-align: center;">Loading...</td></tr>';

        try {
            const resp = await this.adminFetch('/admin/users');
            const data = await resp.json();
            const users = data.users || [];
            countEl.textContent = users.length + ' account(s)';

            if (users.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" style="padding: 8px; text-align: center;">No accounts</td></tr>';
                return;
            }

            tbody.innerHTML = '';
            for (const user of users) {
                const tr = document.createElement('tr');
                const status = user.deactivated ? '🔴 Disabled' : '🟢 Active';
                tr.innerHTML = `
                    <td style="padding: 4px;">${escapeHtml(user.handle)}</td>
                    <td style="padding: 4px;"><code style="font-size: 10px;">${escapeHtml(user.did)}</code></td>
                    <td style="padding: 4px;">${escapeHtml(user.email)}</td>
                    <td style="padding: 4px; text-align: center;">${status}</td>
                    <td style="padding: 4px; text-align: center;">
                        ${user.deactivated
                        ? '<button class="btn" data-enable-did="' + escapeHtml(user.did) + '">Enable</button>'
                        : '<button class="btn" data-disable-did="' + escapeHtml(user.did) + '">Disable</button>'}
                    </td>
                `;
                tbody.appendChild(tr);
            }

            // Attach action handlers
            tbody.querySelectorAll('[data-disable-did]').forEach(btn => {
                btn.addEventListener('click', async () => {
                    const did = btn.dataset.disableDid;
                    try {
                        await this.adminFetch('/xrpc/com.atproto.admin.disableAccountInvites', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ did })
                        });
                        this.loadModeration();
                    } catch (e) {
                        document.getElementById('moderation-result').innerHTML = '<div style="color: red;">' + escapeHtml(e.message) + '</div>';
                    }
                });
            });

            tbody.querySelectorAll('[data-enable-did]').forEach(btn => {
                btn.addEventListener('click', async () => {
                    const did = btn.dataset.enableDid;
                    try {
                        await this.adminFetch('/xrpc/com.atproto.admin.enableAccountInvites', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ did })
                        });
                        this.loadModeration();
                    } catch (e) {
                        document.getElementById('moderation-result').innerHTML = '<div style="color: red;">' + escapeHtml(e.message) + '</div>';
                    }
                });
            });
        } catch (e) {
            tbody.innerHTML = '<tr><td colspan="5" style="padding: 8px; text-align: center; color: red;">Error: ' + escapeHtml(e.message) + '</td></tr>';
        }
    }
};

async function fetchSessionAndCheckAdmin(did, handle) {
    const token = Poster.getAccessToken();
    if (!token) {
        updateUIForLogin(did, handle, false);
        return;
    }
    
    try {
        const resp = await fetch('/xrpc/com.atproto.server.getSession', {
            headers: { 'Authorization': 'Bearer ' + token }
        });
        if (resp.ok) {
            const data = await resp.json();
            sessionIsAdmin = data.isAdmin === true;
            updateUIForLogin(did, handle, sessionIsAdmin);
        } else {
            updateUIForLogin(did, handle, false);
        }
    } catch (e) {
        console.warn('Could not fetch session for admin check:', e);
        updateUIForLogin(did, handle, false);
    }
}

function updateUIForLogin(did, handle, isAdminUser) {
    // Status bar
    const statusUser = document.getElementById('status-user');
    const statusHandle = document.getElementById('status-user-handle');
    if (statusUser && statusHandle) {
        statusHandle.textContent = handle;
        statusUser.style.display = 'inline';
        // Different icon for admins
        statusUser.innerHTML = isAdminUser 
            ? '<span style="color: #666;">\u2699</span> <span id="status-user-handle">' + escapeHtml(handle) + '</span>'
            : '<span style="color: #666;">\u263A</span> <span id="status-user-handle">' + escapeHtml(handle) + '</span>';
    }

    // Menu items
    const loginItem = document.getElementById('menu-login-item');
    const logoutItem = document.getElementById('menu-logout-item');
    const posterItem = document.getElementById('menu-poster-item');
    const fileDivider = document.getElementById('menu-file-divider');
    if (loginItem) loginItem.style.display = 'none';
    if (logoutItem) logoutItem.style.display = '';
    if (posterItem) posterItem.style.display = '';
    if (fileDivider) fileDivider.style.display = '';

    // Admin menu
    if (isAdminUser) {
        const adminGroup = document.getElementById('menu-admin-group');
        if (adminGroup) adminGroup.style.display = '';
    }
}

function updateUIForLogout() {
    sessionIsAdmin = false;
    
    // Status bar
    const statusUser = document.getElementById('status-user');
    if (statusUser) statusUser.style.display = 'none';

    // Menu items
    const loginItem = document.getElementById('menu-login-item');
    const logoutItem = document.getElementById('menu-logout-item');
    const posterItem = document.getElementById('menu-poster-item');
    const fileDivider = document.getElementById('menu-file-divider');
    const adminGroup = document.getElementById('menu-admin-group');
    if (loginItem) loginItem.style.display = '';
    if (logoutItem) logoutItem.style.display = 'none';
    if (posterItem) posterItem.style.display = 'none';
    if (fileDivider) fileDivider.style.display = 'none';
    if (adminGroup) adminGroup.style.display = 'none';

    // Close poster if open
    document.getElementById('win-poster').style.display = 'none';
    document.getElementById('poster-result').innerHTML = '';
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

const ErrorBoundary = {
    showError(containerId, message, retryFn = null) {
        const container = document.getElementById(containerId);
        if (!container) return;
        let html = `<div class="error" role="alert">`;
        html += `<p>${escapeHtml(message)}</p>`;
        if (retryFn) {
            html += `<button class="btn btn-secondary" data-action="retry">Retry</button>`;
        }
        html += `</div>`;
        container.innerHTML = html;
        
        if (retryFn) {
            container.querySelector('[data-action="retry"]')?.addEventListener('click', retryFn);
        }
    },
    
    async withErrorBoundary(containerId, asyncFn, retryFn) {
        const container = document.getElementById(containerId);
        if (container) container.innerHTML = '<p class="loading">Loading...</p>';
        try {
            return await asyncFn();
        } catch (error) {
            console.error('Error in', asyncFn.name || 'asyncFn:', error);
            this.showError(containerId, error.message, retryFn);
            return null;
        }
    }
};


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

export { init, StateManager, ErrorBoundary };
