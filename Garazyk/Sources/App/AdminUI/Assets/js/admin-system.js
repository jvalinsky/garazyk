/**
 * Admin System Tab
 * 
 * Displays server status, audit log, and invite code management
 */

import { AdminPanel } from './admin-panel.js';

let auditLogEntries = [];
let auditFilters = {};

async function load() {
    await Promise.all([
        loadServerStatus(),
        loadAuditLogPreview(),
        loadInviteStats()
    ]);
}

async function loadServerStatus() {
    const container = document.getElementById('admin-system-status');
    if (!container) return;
    
    try {
        const stats = await AdminPanel.getStats();
        
        let html = '<div class="admin-section">';
        html += '<h3>Server Status</h3>';
        html += '<div class="admin-status-grid">';
        html += '<div class="admin-status-item"><span class="admin-status-label">Status</span><span class="admin-status-value">✅ Running</span></div>';
        html += '<div class="admin-status-item"><span class="admin-status-label">Accounts</span><span class="admin-status-value">' + AdminPanel.escapeHtml(stats.accounts_total || '0') + '</span></div>';
        html += '<div class="admin-status-item"><span class="admin-status-label">Repositories</span><span class="admin-status-value">' + AdminPanel.escapeHtml(stats.repos_total || '0') + '</span></div>';
        html += '<div class="admin-status-item"><span class="admin-status-label">Records</span><span class="admin-status-value">' + AdminPanel.escapeHtml(stats.records_total || '0') + '</span></div>';
        html += '</div>';
        html += '</div>';
        
        container.innerHTML = html;
    } catch (err) {
        container.innerHTML = '<p class="error">Failed to load status: ' + AdminPanel.escapeHtml(err.message) + '</p>';
    }
}

async function loadAuditLogPreview() {
    const container = document.getElementById('admin-audit-preview');
    if (!container) return;
    
    try {
        const data = await AdminPanel.getAuditLog({}, 10);
        auditLogEntries = data.entries || [];
        
        let html = '<div class="admin-section">';
        html += '<h3>Recent Admin Actions</h3>';
        
        if (auditLogEntries.length === 0) {
            html += '<p class="empty">No audit log entries</p>';
        } else {
            html += '<ul class="admin-audit-list">';
            auditLogEntries.forEach(entry => {
                const time = entry.created_at ? new Date(entry.created_at).toLocaleString() : '-';
                html += '<li>';
                html += '<span class="admin-audit-time">' + AdminPanel.escapeHtml(time) + '</span>';
                html += '<span class="admin-audit-action">' + AdminPanel.escapeHtml(entry.action) + '</span>';
                if (entry.subject_id) {
                    html += '<span class="admin-audit-subject">' + AdminPanel.escapeHtml(entry.subject_id.substring(0, 20)) + '...</span>';
                }
                html += '</li>';
            });
            html += '</ul>';
            html += '<button class="btn" id="admin-view-full-audit">View Full Audit Log...</button>';
        }
        
        html += '</div>';
        container.innerHTML = html;
        
        const viewBtn = document.getElementById('admin-view-full-audit');
        if (viewBtn) {
            viewBtn.addEventListener('click', showFullAuditLog);
        }
    } catch (err) {
        container.innerHTML = '<p class="error">Failed to load audit log: ' + AdminPanel.escapeHtml(err.message) + '</p>';
    }
}

async function loadInviteStats() {
    const container = document.getElementById('admin-invite-stats');
    if (!container) return;
    
    try {
        const stats = await AdminPanel.getStats();
        
        let html = '<div class="admin-section">';
        html += '<h3>Invite Codes</h3>';
        html += '<div class="admin-stats-row">';
        html += '<span>Total:</span><strong>' + AdminPanel.escapeHtml(stats.invite_codes_total || '0') + '</strong>';
        html += '</div>';
        html += '<div class="admin-stats-row">';
        html += '<span>Active:</span><strong>' + AdminPanel.escapeHtml(stats.invite_codes_active || '0') + '</strong>';
        html += '</div>';
        html += '<button class="btn" id="admin-manage-invites">Manage Invite Codes...</button>';
        html += '</div>';
        
        container.innerHTML = html;
        
        const manageBtn = document.getElementById('admin-manage-invites');
        if (manageBtn) {
            manageBtn.addEventListener('click', () => {
                const win = document.getElementById('win-invite-codes');
                if (win) win.style.display = 'block';
            });
        }
    } catch (err) {
        container.innerHTML = '<p class="error">Failed to load invite stats: ' + AdminPanel.escapeHtml(err.message) + '</p>';
    }
}

function showFullAuditLog() {
    const modal = document.getElementById('admin-audit-modal');
    if (!modal) {
        createAuditModal();
    }
    
    const modalEl = document.getElementById('admin-audit-modal');
    if (modalEl) {
        modalEl.style.display = 'block';
        loadFullAuditLog();
    }
}

function createAuditModal() {
    const modal = document.createElement('div');
    modal.id = 'admin-audit-modal';
    modal.className = 'admin-modal';
    modal.innerHTML = 
        '<div class="admin-modal-content">' +
        '<div class="title-bar"><span class="title">Audit Log</span><button class="close" data-action="close-modal"><span>Close</span></button></div>' +
        '<div class="admin-modal-body">' +
        '<div class="admin-audit-filters">' +
        '<select id="audit-filter-action"><option value="">All Actions</option>' +
        '<option value="account.disable">Account Disable</option>' +
        '<option value="account.enable">Account Enable</option>' +
        '<option value="invite.create">Invite Create</option>' +
        '<option value="report.resolve">Report Resolve</option>' +
        '</select>' +
        '</div>' +
        '<div id="admin-audit-full-list" class="admin-audit-table-container">' +
        '<p class="loading">Loading...</p>' +
        '</div>' +
        '</div>' +
        '</div>';
    
    document.body.appendChild(modal);
    
    const filterSelect = document.getElementById('audit-filter-action');
    if (filterSelect) {
        filterSelect.addEventListener('change', function() {
            auditFilters.action = this.value || null;
            loadFullAuditLog();
        });
    }
}

async function loadFullAuditLog() {
    const container = document.getElementById('admin-audit-full-list');
    if (!container) return;
    
    container.innerHTML = '<p class="loading">Loading audit log...</p>';
    
    try {
        const data = await AdminPanel.getAuditLog(auditFilters, 100);
        const entries = data.entries || [];
        
        if (entries.length === 0) {
            container.innerHTML = '<p class="empty">No audit log entries found</p>';
            return;
        }
        
        let html = '<table class="admin-audit-table">' +
            '<thead><tr>' +
            '<th>Time</th>' +
            '<th>Admin</th>' +
            '<th>Action</th>' +
            '<th>Subject</th>' +
            '<th>Details</th>' +
            '</tr></thead><tbody>';
        
        entries.forEach(entry => {
            const time = entry.created_at ? new Date(entry.created_at).toLocaleString() : '-';
            let details = '';
            if (entry.details) {
                try {
                    const d = typeof entry.details === 'string' ? JSON.parse(entry.details) : entry.details;
                    details = JSON.stringify(d).substring(0, 50);
                } catch (e) {
                    details = String(entry.details).substring(0, 50);
                }
            }
            
            html += '<tr>' +
                '<td>' + AdminPanel.escapeHtml(time) + '</td>' +
                '<td><code>' + AdminPanel.escapeHtml(entry.admin_did ? entry.admin_did.substring(0, 15) + '...' : '-') + '</code></td>' +
                '<td>' + AdminPanel.escapeHtml(entry.action) + '</td>' +
                '<td>' + AdminPanel.escapeHtml(entry.subject_type + ': ' + (entry.subject_id ? entry.subject_id.substring(0, 15) + '...' : '-')) + '</td>' +
                '<td>' + AdminPanel.escapeHtml(details) + '</td>' +
                '</tr>';
        });
        
        html += '</tbody></table>';
        container.innerHTML = html;
    } catch (err) {
        container.innerHTML = '<p class="error">Failed to load: ' + AdminPanel.escapeHtml(err.message) + '</p>';
    }
}

export const AdminSystem = {
    load,
    loadServerStatus,
    loadAuditLogPreview,
    loadInviteStats,
    showFullAuditLog
};
