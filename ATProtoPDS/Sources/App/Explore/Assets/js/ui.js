import { API } from './api.js';
import { CIDDecoder } from './cid.js';
import { renderDidDocument, renderDidSummary } from './did.js';
import { renderPlcOperations } from './plc.js';
import { RecordRenderers } from './records.js';

console.log('ui.js loading...');

let currentDid = null;
let currentCollection = null;
let currentRecord = null;
let viewMode = 'formatted'; // 'formatted' or 'raw'

// Register global helpers early
window.viewCollection = (collection) => {
    console.log('window.viewCollection called for collection:', collection);
    currentCollection = collection;
    showRecords(collection);
};

window.viewRecordDetail = (uri) => {
    console.log('window.viewRecordDetail called for uri:', uri);
    showRecordDetail(uri);
};

function init() {
    // Search Enter key
    document.getElementById('lookup-input').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleLookup();
    });
    
    document.getElementById('cid-decode-btn').addEventListener('click', handleCidDecode);
    document.getElementById('cid-input').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleCidDecode();
    });
    
    document.getElementById('back-collections').addEventListener('click', showCollectionsSection);
    document.getElementById('back-records').addEventListener('click', () => {
        showSection('records', `Records: ${currentCollection || ''}`);
    });
    
    // View toggle buttons
    document.getElementById('view-formatted').addEventListener('click', () => setViewMode('formatted'));
    document.getElementById('view-raw').addEventListener('click', () => setViewMode('raw'));
    
    // Navigation handling
    document.querySelectorAll('.nav-row[data-section]').forEach(row => {
        row.addEventListener('click', (e) => {
            const section = row.dataset.section;
            const label = row.querySelector('.nav-label').textContent;
            
            // Only switch if it's a static section or we have data
            if (section === 'cid-decode') {
                showSection(section, label);
            } else if (currentDid) {
                showSection(section, label);
            } else {
                // If clicking nav items without a DID selected, try to select first account
                const firstAccount = document.querySelector('.account-item');
                if (firstAccount) {
                    firstAccount.click();
                } else {
                    alert('Please search for a DID or select an account first.');
                }
            }
        });
    });
    
    // Initial state
    showSection('did-doc', 'DID Document');
    loadAccounts();
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
    // Highlight account
    document.querySelectorAll('.account-item').forEach(li => {
        li.classList.remove('active');
        if (li.dataset.did === account.did) {
            li.classList.add('active');
        }
    });
    
    currentDid = account.did;
    
    // Update loading states
    document.getElementById('did-content').innerHTML = '<p class="loading">Loading DID document...</p>';
    document.getElementById('plc-content').innerHTML = '<p class="loading">Loading PLC operations...</p>';
    document.getElementById('collections-content').innerHTML = '<p class="loading">Loading collections...</p>';
    
    showSection('did-doc', 'DID Document');
    await showDidDocument(account.did);
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
    
    showSection('did-doc', 'DID Document');
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
    
    // Update nav visibility
    const recordsNav = document.getElementById('nav-records');
    if (recordsNav) {
        recordsNav.style.display = 'flex';
    }
    
    showSection('records', `Records: ${collection}`);
    
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

    // Update nav
    const detailNav = document.getElementById('nav-record-detail');
    if (detailNav) {
        detailNav.style.display = 'flex';
    }
    
    showSection('record-detail', 'Record Detail');
    
    document.getElementById('record-title').textContent = uri;
    document.getElementById('record-formatted').innerHTML = '<p class="loading">Loading...</p>';
    document.getElementById('record-raw').textContent = 'Loading...';
    
    try {
        const record = await API.getRecord(uri);
        console.log('getRecord result:', record);
        currentRecord = record;
        
        if (record.error) {
            document.getElementById('record-formatted').innerHTML = `<p class="error">${escapeHtml(record.error)}</p>`;
            document.getElementById('record-raw').textContent = JSON.stringify(record, null, 2);
        } else {
            // Render formatted view
            document.getElementById('record-formatted').innerHTML = RecordRenderers.render(record);
            // Render raw JSON view
            document.getElementById('record-raw').textContent = JSON.stringify(record, null, 2);
        }
        
        // Apply current view mode
        updateViewDisplay();
    } catch (e) {
        console.error('Failed to get record:', e);
        document.getElementById('record-formatted').innerHTML = `<p class="error">Error: ${escapeHtml(e.message)}</p>`;
        document.getElementById('record-raw').textContent = 'Error: ' + e.message;
    }
}

function setViewMode(mode) {
    viewMode = mode;
    document.getElementById('view-formatted').classList.toggle('active', mode === 'formatted');
    document.getElementById('view-raw').classList.toggle('active', mode === 'raw');
    updateViewDisplay();
}

function updateViewDisplay() {
    const formattedEl = document.getElementById('record-formatted');
    const rawEl = document.getElementById('record-raw');
    
    if (viewMode === 'formatted') {
        formattedEl.style.display = 'block';
        rawEl.style.display = 'none';
    } else {
        formattedEl.style.display = 'none';
        rawEl.style.display = 'block';
    }
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

function showSection(sectionId, breadcrumbLabel) {
    console.log('showSection called for:', sectionId);
    // Hide all sections
    document.querySelectorAll('.doc-section').forEach(s => s.classList.remove('active'));
    
    // Show target section
    const section = document.getElementById(sectionId);
    if (section) {
        section.classList.add('active');
    } else {
        console.error('Section not found:', sectionId);
    }
    
    // Update nav selection
    document.querySelectorAll('.nav-row').forEach(row => row.classList.remove('active'));
    const activeNav = document.querySelector(`.nav-row[data-section="${sectionId}"]`);
    if (activeNav) {
        activeNav.classList.add('active');
        // Ensure all parent nav-items are expanded
        let parentItem = activeNav.closest('.nav-item');
        while (parentItem) {
            parentItem.classList.add('expanded');
            parentItem = parentItem.parentElement.closest('.nav-item');
        }
    }
    
    // Update breadcrumb
    if (breadcrumbLabel) {
        document.getElementById('breadcrumb-current').textContent = breadcrumbLabel;
    }
}

function showCollectionsSection() {
    showSection('collections', 'Collections');
    // Hide temporary nav items
    document.getElementById('nav-records').style.display = 'none';
    document.getElementById('nav-record-detail').style.display = 'none';
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

// Initialize
init();
