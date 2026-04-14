/**
 * Admin Overview Tab
 * 
 * Displays server statistics dashboard
 */

import { AdminPanel } from './admin-panel.js';

const CACHE_TTL = 30000;
let statsCache = null;
let statsCacheTime = 0;

async function getCachedStats() {
    if (statsCache && Date.now() - statsCacheTime < CACHE_TTL) {
        return statsCache;
    }
    statsCache = await AdminPanel.getStats();
    statsCacheTime = Date.now();
    return statsCache;
}

function renderStatCard(label, value, icon) {
    return '<div class="admin-stat-card">' +
        (icon ? '<span class="admin-stat-icon">' + icon + '</span>' : '') +
        '<span class="admin-stat-value">' + AdminPanel.escapeHtml(value) + '</span>' +
        '<span class="admin-stat-label">' + AdminPanel.escapeHtml(label) + '</span>' +
        '</div>';
}

function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function formatNumber(num) {
    if (!num) return '0';
    return parseInt(num, 10).toLocaleString();
}

async function load() {
    const container = document.getElementById('admin-overview-content');
    if (!container) return;
    
    container.innerHTML = '<p class="loading">Loading statistics...</p>';
    
    try {
        const stats = await getCachedStats();
        render(stats);
    } catch (err) {
        container.innerHTML = '<p class="error">Failed to load: ' + AdminPanel.escapeHtml(err.message) + '</p>';
    }
}

function render(stats) {
    const container = document.getElementById('admin-overview-content');
    if (!container) return;
    
    let html = '<div class="admin-stats-grid">';
    
    html += renderStatCard('Total Accounts', formatNumber(stats.accounts_total), '👥');
    html += renderStatCard('Repositories', formatNumber(stats.repos_total), '📦');
    html += renderStatCard('Records', formatNumber(stats.records_total), '📄');
    html += renderStatCard('Blobs', formatNumber(stats.blobs_total), '🖼️');
    
    html += '</div>';
    
    html += '<div class="admin-section">';
    html += '<h3>Storage</h3>';
    html += '<div class="admin-stats-row">';
    html += '<span>Blob Storage:</span>';
    html += '<strong>' + formatBytes(stats.blobs_size_bytes) + '</strong>';
    html += '</div>';
    html += '<div class="admin-stats-row">';
    html += '<span>Blocks:</span>';
    html += '<strong>' + formatNumber(stats.blocks_total) + '</strong>';
    html += '</div>';
    html += '</div>';
    
    html += '<div class="admin-section">';
    html += '<h3>Activity (7 days)</h3>';
    html += '<div class="admin-stats-row">';
    html += '<span>New Signups:</span>';
    html += '<strong>' + formatNumber(stats.recent_signups_7d) + '</strong>';
    html += '</div>';
    html += '</div>';
    
    html += '<div class="admin-section">';
    html += '<h3>Moderation</h3>';
    html += '<div class="admin-stats-row">';
    html += '<span>Open Reports:</span>';
    html += '<strong class="' + (stats.reports_open > 0 ? 'admin-highlight' : '') + '">' + formatNumber(stats.reports_open) + '</strong>';
    html += '</div>';
    html += '</div>';
    
    html += '<div class="admin-section">';
    html += '<h3>Invite Codes</h3>';
    html += '<div class="admin-stats-row">';
    html += '<span>Total:</span>';
    html += '<strong>' + formatNumber(stats.invite_codes_total) + '</strong>';
    html += '</div>';
    html += '<div class="admin-stats-row">';
    html += '<span>Active:</span>';
    html += '<strong>' + formatNumber(stats.invite_codes_active) + '</strong>';
    html += '</div>';
    html += '</div>';
    
    container.innerHTML = html;
}

function refresh() {
    statsCache = null;
    statsCacheTime = 0;
    load();
}

export const AdminOverview = {
    load,
    render,
    refresh
};
