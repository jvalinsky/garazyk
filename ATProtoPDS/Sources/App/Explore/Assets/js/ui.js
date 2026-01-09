import { API } from './api.js';
import { CIDDecoder } from './cid.js';
import { renderDidDocument, renderDidSummary } from './did.js';
import { renderPlcOperations } from './plc.js';

let currentDid = null;
let currentCollection = null;
let currentRecordsCursor = null;

export function init() {
    document.getElementById('lookup-form').addEventListener('submit', handleLookup);
    document.getElementById('cid-decode-btn').addEventListener('click', handleCidDecode);
    document.getElementById('cid-input').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleCidDecode();
    });
    
    document.getElementById('back-collections').addEventListener('click', showCollectionsSection);
    document.getElementById('back-records').addEventListener('click', () => {
        document.getElementById('record-detail').classList.add('hidden');
        document.getElementById('records').classList.remove('hidden');
    });
    
    document.querySelectorAll('.nav-link').forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            const section = link.dataset.section;
            if (section) {
                showSection(section);
            }
        });
    });
    
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
            li.dataset.did = account.did;
            li.dataset.handle = account.handle || '';
            li.innerHTML = `
                <span class="icon-person"></span>
                <span class="account-handle">${escapeHtml(account.handle || account.did)}</span>
            `;
            li.addEventListener('click', () => selectAccount(account));
            list.appendChild(li);
        }
    } else {
        list.innerHTML = '<li class="empty">No accounts found</li>';
    }
}

async function selectAccount(account) {
    document.querySelectorAll('.account-list li').forEach(li => {
        li.classList.remove('active');
        if (li.dataset.did === account.did) {
            li.classList.add('active');
        }
    });
    
    currentDid = account.did;
    await showDidDocument(account.did);
}

async function handleLookup(e) {
    e.preventDefault();
    const input = document.getElementById('lookup-input').value.trim();
    if (!input) return;
    
    const result = await API.lookup(input);
    
    if (result.error) {
        alert('DID/handle not found: ' + result.error);
        return;
    }
    
    currentDid = result.did;
    
    document.querySelectorAll('.account-list li').forEach(li => {
        li.classList.remove('active');
        if (li.dataset.did === result.did) {
            li.classList.add('active');
        }
    });
    
    await showDidDocument(result.did);
    showSection('did-doc');
}

async function showDidDocument(did) {
    const didContent = document.getElementById('did-content');
    const plcContent = document.getElementById('plc-content');
    const collectionsContent = document.getElementById('collections-content');
    
    didContent.innerHTML = '<p class="loading">Loading DID document...</p>';
    plcContent.innerHTML = '<p class="loading">Loading PLC operations...</p>';
    collectionsContent.innerHTML = '<p class="loading">Loading collections...</p>';
    
    const doc = await API.getDidDocument(did);
    if (doc.error) {
        didContent.innerHTML = `<p class="error">${escapeHtml(doc.error)}</p>`;
    } else {
        didContent.innerHTML = renderDidSummary(doc);
    }
    
    const ops = await API.fetchPlcLog(did);
    plcContent.innerHTML = renderPlcOperations(ops);
    
    const describe = await API.getRepoDescribe(did);
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
    
    let html = '<ul class="collection-list">';
    
    for (const collection of describe.collections) {
        html += `
            <li class="collection-item" data-collection="${escapeHtml(collection)}">
                <span class="icon-folder"></span>
                <span class="collection-name">${escapeHtml(collection)}</span>
            </li>
        `;
    }
    
    html += '</ul>';
    content.innerHTML = html;
    
    document.querySelectorAll('.collection-item').forEach(item => {
        item.addEventListener('click', () => {
            currentCollection = item.dataset.collection;
            showRecords(currentCollection);
        });
    });
}

async function showRecords(collection) {
    document.getElementById('records').classList.remove('hidden');
    document.getElementById('record-detail').classList.add('hidden');
    document.getElementById('collections').classList.add('hidden');
    
    document.getElementById('records-title').textContent = collection;
    
    const content = document.getElementById('records-content');
    content.innerHTML = '<p class="loading">Loading records...</p>';
    
    const result = await API.listRecords(collection, { limit: 20 });
    renderRecordsList(result.records, collection);
}

function renderRecordsList(records, collection) {
    const content = document.getElementById('records-content');
    
    if (!records || records.length === 0) {
        content.innerHTML = '<p class="empty">No records in this collection</p>';
        return;
    }
    
    let html = '<ul class="record-list">';
    
    for (const record of records) {
        html += `
            <li class="record-item" data-uri="${escapeHtml(record.uri)}">
                <span class="icon-doc"></span>
                <span class="record-rkey">${escapeHtml(record.rkey)}</span>
                <span class="record-cid">${record.cid ? escapeHtml(record.cid.slice(0, 8)) + '...' : 'N/A'}</span>
            </li>
        `;
    }
    
    html += '</ul>';
    content.innerHTML = html;
    
    document.querySelectorAll('.record-item').forEach(item => {
        item.addEventListener('click', () => {
            showRecordDetail(item.dataset.uri);
        });
    });
}

async function showRecordDetail(uri) {
    document.getElementById('records').classList.add('hidden');
    document.getElementById('record-detail').classList.remove('hidden');
    
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
        resultEl.innerHTML = CIDDecoder.render(decoded);
    } catch (e) {
        resultEl.innerHTML = `<p class="error">${escapeHtml(e.message)}</p>`;
    }
}

function showSection(sectionId) {
    document.querySelectorAll('.section').forEach(s => s.classList.add('hidden'));
    const section = document.getElementById(sectionId);
    if (section) {
        section.classList.remove('hidden');
    }
    
    document.querySelectorAll('.nav-link').forEach(l => {
        l.classList.remove('active');
        if (l.dataset.section === sectionId) {
            l.classList.add('active');
        }
    });
}

function showCollectionsSection() {
    document.getElementById('records').classList.add('hidden');
    document.getElementById('record-detail').classList.add('hidden');
    document.getElementById('collections').classList.remove('hidden');
    showSection('collections');
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
