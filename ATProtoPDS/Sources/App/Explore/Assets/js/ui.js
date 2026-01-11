import { API } from './api.js';
import { CIDDecoder } from './cid.js';
import { renderDidDocument, renderDidSummary } from './did.js';
import { renderPlcOperations } from './plc.js';

let currentDid = null;
let currentCollection = null;

export function init() {
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
            <tr><th>Collection NSID</th><th>Action</th></tr>
    `;
    
    for (const collection of describe.collections) {
        html += `
            <tr>
                <td><code>${escapeHtml(collection)}</code></td>
                <td><button class="btn-secondary" onclick="window.viewCollection('${escapeHtml(collection)}')">View Records</button></td>
            </tr>
        `;
    }
    
    html += '</table>';
    content.innerHTML = html;
}

// Global helper for the button onclick
window.viewCollection = (collection) => {
    currentCollection = collection;
    showRecords(collection);
};

async function showRecords(collection) {
    showSection('records', `Records: ${collection}`);
    
    // Update nav visibility
    const recordsNav = document.getElementById('nav-records');
    recordsNav.style.display = 'flex';
    recordsNav.click(); // Select it
    
    document.getElementById('records-title').textContent = collection;
    
    const content = document.getElementById('records-content');
    content.innerHTML = '<p class="loading">Loading records...</p>';
    
    const result = await API.listRecords(currentDid, collection, { limit: 20 });
    renderRecordsList(result.records, collection);
}

function renderRecordsList(records, collection) {
    const content = document.getElementById('records-content');
    
    if (!records || records.length === 0) {
        content.innerHTML = '<p class="empty">No records in this collection</p>';
        return;
    }
    
    let html = `
        <p class="description">Found <strong>${records.length}</strong> records in ${collection}.</p>
        <table>
            <tr><th>RKey</th><th>CID</th><th>Action</th></tr>
    `;
    
    for (const record of records) {
        const displayCid = record.cid ? record.cid.slice(0, 12) + '...' : 'N/A';
        html += `
            <tr>
                <td><code>${escapeHtml(record.rkey)}</code></td>
                <td><code>${escapeHtml(displayCid)}</code></td>
                <td><button class="btn-secondary" onclick="window.viewRecordDetail('${escapeHtml(record.uri)}')">View Detail</button></td>
            </tr>
        `;
    }
    
    html += '</table>';
    content.innerHTML = html;
}

window.viewRecordDetail = (uri) => {
    showRecordDetail(uri);
};

async function showRecordDetail(uri) {
    showSection('record-detail', 'Record Detail');
    
    // Update nav
    const detailNav = document.getElementById('nav-record-detail');
    detailNav.style.display = 'flex';
    detailNav.click();
    
    document.getElementById('record-title').textContent = uri;
    document.getElementById('record-content').textContent = 'Loading...';
    
    const record = await API.getRecord(uri);
    if (record.error) {
        document.getElementById('record-content').textContent = record.error;
    } else {
        document.getElementById('record-content').textContent = JSON.stringify(record, null, 2);
    }
}

async function handleCidDecode() {
    const cid = document.getElementById('cid-input').value.trim();
    if (!cid) return;
    
    const resultEl = document.getElementById('cid-result');
    resultEl.innerHTML = '<p class="loading">Decoding...</p>';
    
    try {
        const decoded = CIDDecoder.decode(cid);
        // Custom render for the new style
        let html = '<div style="margin-top:20px">';
        html += `<h3>CID Version ${decoded.version}</h3>`;
        html += '<table><tr><th>Property</th><th>Value</th></tr>';
        html += `<tr><td>Codec</td><td>${decoded.codec} (0x${decoded.code.toString(16)})</td></tr>`;
        html += `<tr><td>Multihash</td><td>${decoded.multihashName} (0x${decoded.multihashCode.toString(16)})</td></tr>`;
        html += `<tr><td>Digest Size</td><td>${decoded.size} bytes</td></tr>`;
        html += '</table>';
        html += '</div>';
        
        resultEl.innerHTML = html;
    } catch (e) {
        resultEl.innerHTML = `<p class="error">${escapeHtml(e.message)}</p>`;
    }
}

function showSection(sectionId, breadcrumbLabel) {
    // Hide all sections
    document.querySelectorAll('.doc-section').forEach(s => s.classList.remove('active'));
    
    // Show target section
    const section = document.getElementById(sectionId);
    if (section) {
        section.classList.add('active');
    }
    
    // Update nav selection
    document.querySelectorAll('.nav-row').forEach(row => row.classList.remove('active'));
    const activeNav = document.querySelector(`.nav-row[data-section="${sectionId}"]`);
    if (activeNav) {
        activeNav.classList.add('active');
        // Ensure parent tree is expanded
        activeNav.closest('.nav-item').classList.add('expanded');
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

document.addEventListener('DOMContentLoaded', init);
