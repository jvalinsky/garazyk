// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * Stats Renderer
 * Displays statistics about the MST
 */

export class StatsRenderer {
    constructor(container) {
        this.container = container;
    }

    /**
     * Render statistics
     * @param {Object} stats - Statistics object from API
     */
    render(stats) {
        if (!stats || stats.error) {
            this.renderError(stats?.error || 'No statistics');
            return;
        }

        let html = '';

        // Tree Statistics
        if (stats.node_count !== undefined) {
            html += this.renderStatItem('Total Nodes', stats.node_count);
        }

        if (stats.leaf_count !== undefined) {
            html += this.renderStatItem('Leaf Nodes', stats.leaf_count);
        }

        if (stats.internal_count !== undefined) {
            html += this.renderStatItem('Internal Nodes', stats.internal_count);
        }

        if (stats.tree_depth !== undefined) {
            html += this.renderStatItem('Tree Depth', stats.tree_depth);
        }

        if (stats.avg_children !== undefined) {
            html += this.renderStatItem(
                'Avg Children per Node',
                stats.avg_children.toFixed(2)
            );
        }

        // Size Statistics
        if (stats.total_size !== undefined) {
            html += this.renderStatItem(
                'Total Size',
                this.formatBytes(stats.total_size)
            );
        }

        if (stats.node_size !== undefined) {
            html += this.renderStatItem(
                'Avg Node Size',
                this.formatBytes(stats.node_size)
            );
        }

        // Update Statistics
        if (stats.last_updated !== undefined) {
            html += this.renderStatItem(
                'Last Updated',
                this.formatDate(stats.last_updated)
            );
        }

        if (stats.created_at !== undefined) {
            html += this.renderStatItem(
                'Created',
                this.formatDate(stats.created_at)
            );
        }

        // Balance Statistics
        if (stats.balance_factor !== undefined) {
            html += this.renderStatItem(
                'Balance Factor',
                stats.balance_factor.toFixed(3),
                'Balance factor close to 1.0 indicates a well-balanced tree'
            );
        }

        // Root Information
        if (stats.root_cid) {
            html += `<div class="stat-item">`;
            html += `<div class="stat-label">Root CID</div>`;
            html += `<div class="stat-value stat-value-cid">`;
            html += `${this.escapeHtml(stats.root_cid)}`;
            html += `</div>`;
            html += `</div>`;
        }

        // Additional Info
        if (stats.algorithm) {
            html += this.renderStatItem('Algorithm', this.escapeHtml(stats.algorithm));
        }

        if (stats.version) {
            html += this.renderStatItem('Version', this.escapeHtml(stats.version));
        }

        this.container.innerHTML = html || '<p class="placeholder">No statistics available</p>';
    }

    /**
     * Render a single stat item
     * @param {string} label - Stat label
     * @param {*} value - Stat value
     * @param {string} secondary - Optional secondary text
     * @returns {string} HTML string
     */
    renderStatItem(label, value, secondary = null) {
        let html = `<div class="stat-item">`;
        html += `<div class="stat-label">${this.escapeHtml(label)}</div>`;
        html += `<div class="stat-value">${this.escapeHtml(String(value))}</div>`;
        if (secondary) {
            html += `<div class="stat-secondary">${this.escapeHtml(secondary)}</div>`;
        }
        html += `</div>`;
        return html;
    }

    /**
     * Render error state
     * @param {string} error - Error message
     */
    renderError(error) {
        this.container.innerHTML = `
            <div class="placeholder error">
                <p>Error loading statistics:</p>
                <p class="stats-error-text">${this.escapeHtml(error)}</p>
            </div>
        `;
    }

    /**
     * Format bytes to human readable size
     * @param {number} bytes - Number of bytes
     * @returns {string} Formatted size
     */
    formatBytes(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
    }

    /**
     * Format date to readable format
     * @param {string|number} date - Date string or timestamp
     * @returns {string} Formatted date
     */
    formatDate(date) {
        try {
            const d = new Date(typeof date === 'string' ? date : date * 1000);
            return d.toLocaleDateString() + ' ' + d.toLocaleTimeString();
        } catch (e) {
            return String(date);
        }
    }

    /**
     * Escape HTML special characters
     * @param {string} str - String to escape
     * @returns {string} Escaped string
     */
    escapeHtml(str) {
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

    /**
     * Clear the renderer
     */
    clear() {
        this.container.innerHTML = '<p class="placeholder">Select an account to view statistics.</p>';
    }

    /**
     * Destroy the renderer
     */
    destroy() {
        this.clear();
    }
}

export default StatsRenderer;
