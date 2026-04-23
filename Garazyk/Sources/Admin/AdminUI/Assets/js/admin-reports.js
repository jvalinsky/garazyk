/**
 * Admin Reports/Moderation Tab
 * 
 * Displays moderation reports queue with resolution actions
 */

import { AdminPanel } from './admin-panel.js';

let reportsList = [];
let selectedReportId = null;
let statusFilter = '';
let reasonTypeFilter = '';

const REASON_LABELS = {
    'com.atproto.moderation.defs#reasonSpam': 'Spam',
    'com.atproto.moderation.defs#reasonViolation': 'TOS Violation',
    'com.atproto.moderation.defs#reasonMisleading': 'Misleading',
    'com.atproto.moderation.defs#reasonSexual': 'Sexual Content',
    'com.atproto.moderation.defs#reasonRude': 'Rude/Offensive',
    'com.atproto.moderation.defs#reasonOther': 'Other'
};

const STATUS_LABELS = {
    'open': 'Open',
    'in_progress': 'In Progress',
    'resolved': 'Resolved',
    'dismissed': 'Dismissed'
};

async function load() {
    const container = document.getElementById('admin-reports-list');
    if (!container) return;
    
    container.innerHTML = `<div class="loading-state">
      <div class="loading-indicator"></div>
      <span class="loading-state-title">Loading reports...</span>
    </div>`;
    
    try {
        const filters = {};
        if (statusFilter) filters.status = statusFilter;
        if (reasonTypeFilter) filters.reasonType = reasonTypeFilter;
        
        const data = await AdminPanel.getReports(filters, 50);
        reportsList = data.reports || [];
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
          <span class="loading-state-title">Failed to load reports</span>
          <span class="loading-state-description">${AdminPanel.escapeHtml(err.message)}</span>
        </div>`;
        window.AdminUI?.showError?.('Failed to load reports: ' + err.message);
    }
}

function render() {
    const container = document.getElementById('admin-reports-list');
    if (!container) return;
    
    if (reportsList.length === 0) {
        container.innerHTML = `<div class="loading-state">
          <div class="empty-state-strawberry"></div>
          <span class="loading-state-title">No reports found</span>
          <span class="loading-state-description">All moderation reports have been resolved.</span>
        </div>`;
        updateReportCount(0);
        return;
    }
    
    updateReportCount(reportsList.length);
    container.innerHTML = '';
    
    reportsList.forEach(report => {
        const li = document.createElement('li');
        li.className = 'admin-report-item';
        li.dataset.reportId = report.report_id;
        
        const statusClass = 'admin-status-' + report.status;
        const reasonLabel = REASON_LABELS[report.reason_type] || report.reason_type;
        
        let subjectDisplay = '-';
        if (report.subject_type === 'account' && report.subject_did) {
            subjectDisplay = report.subject_did.substring(0, 20) + '...';
        } else if (report.subject_type === 'record' && report.subject_uri) {
            subjectDisplay = report.subject_uri.substring(0, 30) + '...';
        }
        
        const statusIcon = report.status === 'open' ? '🔴' : 
                          report.status === 'in_progress' ? '🟡' : 
                          report.status === 'resolved' ? '🟢' : '⚪';
        
        li.innerHTML = '<span class="admin-report-status">' + statusIcon + '</span>' +
            '<span class="admin-report-reason">' + AdminPanel.escapeHtml(reasonLabel) + '</span>' +
            '<span class="admin-report-subject">' + AdminPanel.escapeHtml(subjectDisplay) + '</span>';
        
        li.addEventListener('click', () => selectReport(report));
        
        if (selectedReportId === report.report_id) {
            li.classList.add('selected');
        }
        
        container.appendChild(li);
    });
}

function updateReportCount(count) {
    const countEl = document.getElementById('admin-reports-count');
    if (countEl) countEl.textContent = count + ' report(s)';
}

function selectReport(report) {
    selectedReportId = report.report_id;
    
    document.querySelectorAll('.admin-report-item').forEach(li => {
        li.classList.toggle('selected', li.dataset.reportId === report.report_id);
    });
    
    renderDetail(report);
}

function renderDetail(report) {
    const container = document.getElementById('admin-reports-detail');
    if (!container) return;
    
    const reasonLabel = REASON_LABELS[report.reason_type] || report.reason_type;
    const statusLabel = STATUS_LABELS[report.status] || report.status;
    
    let html = '<div class="admin-detail-section">';
    html += '<h4>Report #' + AdminPanel.escapeHtml(report.report_id ? report.report_id.substring(0, 8) : 'Unknown') + '</h4>';
    
    html += '<div class="admin-detail-row"><label>Status:</label><span class="admin-status-' + report.status + '">' + statusLabel + '</span></div>';
    html += '<div class="admin-detail-row"><label>Reason:</label><span>' + AdminPanel.escapeHtml(reasonLabel) + '</span></div>';
    
    if (report.reason) {
        html += '<div class="admin-detail-row"><label>Details:</label><span>' + AdminPanel.escapeHtml(report.reason) + '</span></div>';
    }
    
    html += '<div class="admin-detail-row"><label>Reporter:</label><code>' + AdminPanel.escapeHtml(report.reported_by_did || 'Unknown') + '</code></div>';
    
    html += '<div class="admin-detail-row"><label>Subject Type:</label><span>' + AdminPanel.escapeHtml(report.subject_type || '-') + '</span></div>';
    
    if (report.subject_did) {
        html += '<div class="admin-detail-row"><label>Subject DID:</label><code>' + AdminPanel.escapeHtml(report.subject_did) + '</code></div>';
    }
    
    if (report.subject_uri) {
        html += '<div class="admin-detail-row"><label>Subject URI:</label><code>' + AdminPanel.escapeHtml(report.subject_uri) + '</code></div>';
    }
    
    html += '<div class="admin-detail-row"><label>Created:</label><span>' + AdminPanel.escapeHtml(report.created_at || '-') + '</span></div>';
    
    if (report.resolved_by_did) {
        html += '<div class="admin-detail-row"><label>Resolved By:</label><code>' + AdminPanel.escapeHtml(report.resolved_by_did) + '</code></div>';
        html += '<div class="admin-detail-row"><label>Resolved At:</label><span>' + AdminPanel.escapeHtml(report.resolved_at || '-') + '</span></div>';
    }
    
    if (report.resolution_notes) {
        html += '<div class="admin-detail-row"><label>Notes:</label><span>' + AdminPanel.escapeHtml(report.resolution_notes) + '</span></div>';
    }
    
    html += '</div>';
    
    if (report.status === 'open' || report.status === 'in_progress') {
        html += '<div class="admin-detail-actions">';
        html += '<button class="btn" data-action="dismiss" data-report="' + AdminPanel.escapeHtml(report.report_id) + '">Dismiss</button>';
        html += '<button class="btn btn-default" data-action="resolve" data-report="' + AdminPanel.escapeHtml(report.report_id) + '">Resolve</button>';
        html += '</div>';
    }
    
    container.innerHTML = html;
    
    container.querySelectorAll('[data-action]').forEach(btn => {
        btn.addEventListener('click', handleAction);
    });
}

async function handleAction(event) {
    const btn = event.currentTarget;
    const action = btn.dataset.action;
    const reportId = btn.dataset.report;
    const resultEl = document.getElementById('admin-reports-result');
    const status = action === 'dismiss' ? 'dismissed' : 'resolved';

    const Sheet = window.AdminUI?.SheetDialog || window.SheetDialog;
    Sheet.prompt({
        title: 'Resolution Notes',
        label: 'Enter resolution notes (optional):',
        initialValue: '',
        placeholder: 'Add notes about this resolution...',
        confirmLabel: status === 'resolved' ? 'Resolve' : 'Dismiss',
        onConfirm: async (notes) => {
            try {
                btn.disabled = true;
                btn.textContent = 'Processing...';

                await AdminPanel.resolveReport(reportId, status, notes);

                if (resultEl) resultEl.innerHTML = '<div class="admin-success">Report ' + status + '</div>';
                load();
            } catch (err) {
                if (resultEl) resultEl.innerHTML = '<div class="admin-error">' + AdminPanel.escapeHtml(err.message) + '</div>';
                btn.disabled = false;
                btn.textContent = action === 'dismiss' ? 'Dismiss' : 'Resolve';
            }
        }
    });
}

function setStatusFilter(status) {
    statusFilter = status;
    selectedReportId = null;
    load();
}

function setReasonFilter(reason) {
    reasonTypeFilter = reason;
    selectedReportId = null;
    load();
}

export const AdminReports = {
    load,
    render,
    setStatusFilter,
    setReasonFilter,
    REASON_LABELS,
    STATUS_LABELS
};
