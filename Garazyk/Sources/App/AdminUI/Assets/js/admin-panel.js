/**
 * Admin Control Panel - Main Module
 * 
 * Provides the unified admin interface with 4 tabs:
 * Overview, Accounts, Moderation, System
 */

const API_BASE = '/admin';
const XRPC_BASE = '/xrpc';

let currentTab = 'overview';
let adminToken = null;

function escapeHtml(str) {
    if (!str) return '';
    if (typeof str !== 'string') str = String(str);
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

async function adminFetch(url, opts = {}) {
    const token = getToken();
    const headers = { ...(opts.headers || {}) };
    if (token) {
        headers['Authorization'] = 'Bearer ' + token;
    }
    const resp = await fetch(url, { ...opts, headers });
    if (resp.status === 401) {
        clearToken();
        throw new Error('Admin session expired');
    }
    return resp;
}

function getToken() {
    if (adminToken) return adminToken;
    adminToken = sessionStorage.getItem('admin_token');
    return adminToken;
}

function setToken(token) {
    adminToken = token;
    sessionStorage.setItem('admin_token', token);
}

function clearToken() {
    adminToken = null;
    sessionStorage.removeItem('admin_token');
}

function isAuthenticated() {
    return !!getToken();
}

async function login(password) {
    const resp = await fetch(API_BASE + '/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password })
    });
    const data = await resp.json();
    if (resp.ok && data.token) {
        setToken(data.token);
        return data;
    }
    throw new Error(data.error || 'Login failed');
}

function logout() {
    clearToken();
}

async function getStats() {
    const resp = await adminFetch(API_BASE + '/stats');
    if (!resp.ok) throw new Error('Failed to get stats');
    return resp.json();
}

async function getAuditLog(filters = {}, limit = 50, cursor = null) {
    const params = new URLSearchParams();
    if (filters.admin_did) params.set('admin_did', filters.admin_did);
    if (filters.action) params.set('action', filters.action);
    if (filters.subject_type) params.set('subject_type', filters.subject_type);
    if (filters.subject_id) params.set('subject_id', filters.subject_id);
    if (filters.since) params.set('since', filters.since);
    if (filters.until) params.set('until', filters.until);
    if (limit) params.set('limit', limit);
    if (cursor) params.set('cursor', cursor);
    
    const resp = await adminFetch(API_BASE + '/audit-log?' + params.toString());
    if (!resp.ok) throw new Error('Failed to get audit log');
    return resp.json();
}

async function getReports(filters = {}, limit = 50, cursor = null) {
    const params = new URLSearchParams();
    if (filters.status) params.set('status', filters.status);
    if (filters.reasonType) params.set('reasonType', filters.reasonType);
    if (filters.subjectDid) params.set('subjectDid', filters.subjectDid);
    if (filters.reportedBy) params.set('reportedBy', filters.reportedBy);
    if (limit) params.set('limit', limit);
    if (cursor) params.set('cursor', cursor);
    
    const resp = await adminFetch(XRPC_BASE + '/com.atproto.admin.getModerationReports?' + params.toString());
    if (!resp.ok) throw new Error('Failed to get reports');
    return resp.json();
}

async function resolveReport(reportId, status, notes = null) {
    const resp = await adminFetch(XRPC_BASE + '/com.atproto.admin.resolveReport', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: reportId, status, notes })
    });
    if (!resp.ok) {
        const data = await resp.json().catch(() => ({}));
        throw new Error(data.message || 'Failed to resolve report');
    }
    return resp.json();
}

async function getUsers() {
    const resp = await adminFetch(API_BASE + '/users');
    if (!resp.ok) throw new Error('Failed to get users');
    return resp.json();
}

async function disableAccount(did) {
    const resp = await adminFetch(XRPC_BASE + '/com.atproto.admin.disableAccountInvites', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ did })
    });
    if (!resp.ok) {
        const data = await resp.json().catch(() => ({}));
        throw new Error(data.message || 'Failed to disable account');
    }
    return resp.json();
}

async function enableAccount(did) {
    const resp = await adminFetch(XRPC_BASE + '/com.atproto.admin.enableAccountInvites', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ did })
    });
    if (!resp.ok) {
        const data = await resp.json().catch(() => ({}));
        throw new Error(data.message || 'Failed to enable account');
    }
    return resp.json();
}

export const AdminPanel = {
    getToken,
    setToken,
    clearToken,
    isAuthenticated,
    login,
    logout,
    getStats,
    getAuditLog,
    getReports,
    resolveReport,
    getUsers,
    disableAccount,

    closeModal(el) {
        const modal = el.closest('.admin-modal');
        if (modal) modal.style.display = 'none';
    },

    initEventDelegation() {
        document.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-action="close-modal"]');
            if (btn) this.closeModal(btn);
        });
    },

    enableAccount,
    escapeHtml,
    
    getCurrentTab() {
        return currentTab;
    },
    
    switchTab(tabId) {
        currentTab = tabId;
        document.querySelectorAll('.admin-tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.admin-tab-content').forEach(c => c.classList.remove('active'));
        
        const tab = document.querySelector('[data-tab="' + tabId + '"]');
        const content = document.getElementById('admin-tab-' + tabId);
        
        if (tab) tab.classList.add('active');
        if (content) content.classList.add('active');
    },
    
    show() {
        const panel = document.getElementById('win-admin-panel');
        if (panel) {
            panel.style.display = 'block';
            panel.style.zIndex = 1000;
            this.switchTab('overview');
        }
    },
    
    hide() {
        const panel = document.getElementById('win-admin-panel');
        if (panel) panel.style.display = 'none';
    }
};
