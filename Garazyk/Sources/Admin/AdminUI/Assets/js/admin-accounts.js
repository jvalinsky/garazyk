/**
 * Admin Accounts Tab
 * 
 * Displays user list with search and account management actions
 */

import { AdminPanel } from './admin-panel.js';

let accountsList = [];
let selectedDid = null;
let searchQuery = '';

async function load() {
    const container = document.getElementById('admin-accounts-list');
    if (!container) return;
    
    container.innerHTML = `<div class="loading-state">
      <div class="loading-indicator"></div>
      <span class="loading-state-title">Loading accounts...</span>
    </div>`;
    
    try {
        const data = await AdminPanel.getUsers();
        accountsList = data.users || [];
        render();
    } catch (err) {
        container.innerHTML = `<div class="loading-state">
          <div class="empty-state-icon">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
              <circle cx="12" cy="12" r="10"></circle>
              <line x1="12" y1="8" x2="12" y2="12"></line>
              <line x1="12" y1="16" x2="12.01" y2="16"></line>
            </svg>
          </div>
          <span class="loading-state-title">Failed to load accounts</span>
          <span class="loading-state-description">${AdminPanel.escapeHtml(err.message)}</span>
        </div>`;
        window.AdminUI?.showError?.('Failed to load accounts: ' + err.message);
    }
}

function getFilteredAccounts() {
    if (!searchQuery) return accountsList;
    const q = searchQuery.toLowerCase();
    return accountsList.filter(a => 
        (a.handle && a.handle.toLowerCase().includes(q)) ||
        (a.did && a.did.toLowerCase().includes(q)) ||
        (a.email && a.email.toLowerCase().includes(q))
    );
}

function render() {
    const container = document.getElementById('admin-accounts-list');
    if (!container) return;
    
    const filtered = getFilteredAccounts();
    
    if (filtered.length === 0) {
        container.innerHTML = `<div class="loading-state">
          <div class="empty-state-strawberry"></div>
          <span class="loading-state-title">No accounts found</span>
          <span class="loading-state-description">${searchQuery ? 'Try adjusting your search query.' : 'No user accounts on this PDS.'}</span>
        </div>`;
        return;
    }
    
    container.innerHTML = '';
    
    filtered.forEach(account => {
        const li = document.createElement('li');
        li.className = 'admin-account-item';
        li.dataset.did = account.did;
        
        const status = account.deactivated ? 'disabled' : 'active';
        const statusIcon = status === 'active' ? '🟢' : '🔴';
        
        li.innerHTML = '<span class="admin-account-status">' + statusIcon + '</span>' +
            '<span class="admin-account-handle">' + AdminPanel.escapeHtml(account.handle || account.did) + '</span>';
        
        li.addEventListener('click', () => selectAccount(account));
        
        if (selectedDid === account.did) {
            li.classList.add('selected');
        }
        
        container.appendChild(li);
    });
}

function selectAccount(account) {
    selectedDid = account.did;
    
    document.querySelectorAll('.admin-account-item').forEach(li => {
        li.classList.toggle('selected', li.dataset.did === account.did);
    });
    
    renderDetail(account);
}

function renderDetail(account) {
    const container = document.getElementById('admin-accounts-detail');
    if (!container) return;
    
    const status = account.deactivated ? 'Disabled' : 'Active';
    const statusClass = account.deactivated ? 'admin-status-disabled' : 'admin-status-active';
    
    let html = '<div class="admin-detail-section">';
    html += '<h4>' + AdminPanel.escapeHtml(account.handle || 'Unknown') + '</h4>';
    html += '<div class="admin-detail-row"><label>DID:</label><code>' + AdminPanel.escapeHtml(account.did) + '</code></div>';
    html += '<div class="admin-detail-row"><label>Email:</label><span>' + AdminPanel.escapeHtml(account.email || '-') + '</span></div>';
    html += '<div class="admin-detail-row"><label>Status:</label><span class="' + statusClass + '">' + status + '</span></div>';
    html += '<div class="admin-detail-row"><label>Created:</label><span>' + AdminPanel.escapeHtml(account.created_at || '-') + '</span></div>';
    html += '</div>';
    
    html += '<div class="admin-detail-actions">';
    
    if (account.deactivated) {
        html += '<button class="btn btn-default" data-action="enable" data-did="' + AdminPanel.escapeHtml(account.did) + '">Enable Account</button>';
    } else {
        html += '<button class="btn" data-action="disable" data-did="' + AdminPanel.escapeHtml(account.did) + '">Disable Account</button>';
    }
    
    html += '<button class="btn" data-action="info" data-did="' + AdminPanel.escapeHtml(account.did) + '">Get Info...</button>';
    html += '</div>';
    
    container.innerHTML = html;
    
    container.querySelectorAll('[data-action]').forEach(btn => {
        btn.addEventListener('click', handleAction);
    });
}

async function handleAction(event) {
    const btn = event.currentTarget;
    const action = btn.dataset.action;
    const did = btn.dataset.did;
    
    const resultEl = document.getElementById('admin-accounts-result');
    
    try {
        if (action === 'disable') {
            btn.disabled = true;
            btn.textContent = 'Disabling...';
            await AdminPanel.disableAccount(did);
            if (resultEl) resultEl.innerHTML = '<div class="admin-success">Account disabled</div>';
            load();
        } else if (action === 'enable') {
            btn.disabled = true;
            btn.textContent = 'Enabling...';
            await AdminPanel.enableAccount(did);
            if (resultEl) resultEl.innerHTML = '<div class="admin-success">Account enabled</div>';
            load();
        } else if (action === 'info') {
            showAccountInfo(did);
        }
    } catch (err) {
        if (resultEl) resultEl.innerHTML = '<div class="admin-error">' + AdminPanel.escapeHtml(err.message) + '</div>';
        btn.disabled = false;
        btn.textContent = action === 'disable' ? 'Disable Account' : 'Enable Account';
    }
}

function showAccountInfo(did) {
    const account = accountsList.find(a => a.did === did);
    if (!account) return;

    const status = account.deactivated ? 'Disabled' : 'Active';
    const info = [
        { label: 'Handle', value: account.handle || '-' },
        { label: 'DID', value: account.did },
        { label: 'Email', value: account.email || '-' },
        { label: 'Created', value: account.created_at || '-' },
        { label: 'Deactivated', value: account.deactivated ? 'Yes' : 'No' },
        { label: 'Invite Enabled', value: account.invite_enabled ? 'Yes' : 'No' }
    ];

    const Sheet = window.AdminUI?.SheetDialog || window.SheetDialog;
    Sheet.open({
        title: 'Account Info: ' + (account.handle || did.substring(0, 20)),
        fields: info.map(item => ({
            name: item.label.toLowerCase().replace(/\s+/g, '_'),
            label: item.label,
            type: 'text',
            value: item.value,
            readonly: true
        })),
        confirmLabel: 'Close',
        onConfirm: () => {}
    });
}

function search(query) {
    searchQuery = query.trim().toLowerCase();
    render();
}

export const AdminAccounts = {
    load,
    render,
    search,
    selectAccount
};
