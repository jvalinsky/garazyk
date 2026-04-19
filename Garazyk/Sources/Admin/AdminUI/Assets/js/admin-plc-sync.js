/**
 * Admin PLC + Sync operator controls.
 */

import { AdminPanel } from './admin-panel.js';

export function init() {
    document.addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-action]');
        if (!btn) return;

        const action = btn.dataset.action;
        if (!action.startsWith('plc-') && !action.startsWith('sync-')) return;

        e.preventDefault();

        try {
            if (action === 'plc-request-signature') {
                const data = await jsonRequest('/xrpc/com.atproto.identity.requestPlcOperationSignature', {
                    method: 'POST',
                    body: {}
                });
                if (data.token) {
                    const tokenInput = document.getElementById('plc-token-input');
                    if (tokenInput) tokenInput.value = data.token;
                }
                writeJSON('plc-operation-output', data);
            } else if (action === 'plc-sign-operation') {
                const token = readValue('plc-token-input');
                if (!token) throw new Error('PLC token is required');

                const data = await jsonRequest('/xrpc/com.atproto.identity.signPlcOperation', {
                    method: 'POST',
                    body: { token }
                });

                writeJSON('plc-operation-output', data);
                const op = data.operation || (data.body && data.body.operation);
                if (op) {
                    const operationTextarea = document.getElementById('plc-operation-json');
                    if (operationTextarea) {
                        operationTextarea.value = JSON.stringify(op, null, 2);
                    }
                }
            } else if (action === 'plc-submit-operation') {
                const operationJSON = readValue('plc-operation-json');
                if (!operationJSON) throw new Error('Signed operation JSON is required');

                let operation;
                try {
                    operation = JSON.parse(operationJSON);
                } catch (err) {
                    throw new Error('Signed operation must be valid JSON');
                }

                const data = await jsonRequest('/xrpc/com.atproto.identity.submitPlcOperation', {
                    method: 'POST',
                    body: { operation }
                });
                writeJSON('plc-operation-output', data);
            } else if (action === 'sync-list-hosts') {
                const data = await jsonRequest('/xrpc/com.atproto.sync.listHosts', { method: 'GET' });
                renderHosts(data.hosts || []);
                writeJSON('sync-action-output', data);
            } else if (action === 'sync-get-host-status') {
                const hostname = readValue('sync-hostname-input');
                if (!hostname) throw new Error('Hostname is required');
                const data = await jsonRequest('/xrpc/com.atproto.sync.getHostStatus?hostname=' + encodeURIComponent(hostname), {
                    method: 'GET'
                });
                writeJSON('sync-action-output', data);
            } else if (action === 'sync-request-crawl') {
                const hostname = readValue('sync-hostname-input');
                if (!hostname) throw new Error('Hostname is required');
                const data = await jsonRequest('/xrpc/com.atproto.sync.requestCrawl', {
                    method: 'POST',
                    body: { hostname }
                });
                writeJSON('sync-action-output', data);
            } else if (action === 'sync-notify-update') {
                const hostname = readValue('sync-hostname-input');
                if (!hostname) throw new Error('Hostname is required');
                const data = await jsonRequest('/xrpc/com.atproto.sync.notifyOfUpdate', {
                    method: 'POST',
                    body: { hostname }
                });
                writeJSON('sync-action-output', data);
            } else if (action === 'sync-get-repo-status') {
                const did = readValue('sync-repo-did-input');
                if (!did) throw new Error('Repository DID is required');
                const data = await jsonRequest('/xrpc/com.atproto.sync.getRepoStatus?did=' + encodeURIComponent(did), {
                    method: 'GET'
                });
                writeJSON('sync-repo-output', data);
            }
        } catch (err) {
            window.AdminUI.showError(err.message || 'Operation failed');
        }
    });
}

async function jsonRequest(url, { method, body }) {
    const headers = {
        'Authorization': 'Bearer ' + AdminPanel.getToken()
    };
    const request = { method, headers };

    if (body !== undefined) {
        headers['Content-Type'] = 'application/json';
        request.body = JSON.stringify(body);
    }

    const response = await fetch(url, request);
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
        throw new Error(data.message || data.error || ('Request failed (' + response.status + ')'));
    }
    return data;
}

function readValue(id) {
    const el = document.getElementById(id);
    return el ? el.value.trim() : '';
}

function writeJSON(id, data) {
    const target = document.getElementById(id);
    if (target) {
        target.textContent = JSON.stringify(data || {}, null, 2);
    }
}

function renderHosts(hosts) {
    const tbody = document.getElementById('sync-hosts-list');
    if (!tbody) return;

    if (!hosts.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="text-center text-secondary">No hosts found.</td></tr>';
        return;
    }

    tbody.innerHTML = hosts.map((host) => {
        return '<tr>' +
            '<td><code>' + escapeHTML(host.hostname || '') + '</code></td>' +
            '<td>' + escapeHTML(host.status || '') + '</td>' +
            '<td>' + escapeHTML(String(host.seq ?? '')) + '</td>' +
            '<td>' + escapeHTML(String(host.accountCount ?? '')) + '</td>' +
            '</tr>';
    }).join('');
}

function escapeHTML(value) {
    return String(value || '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

export const AdminPlcSync = {
    init
};
