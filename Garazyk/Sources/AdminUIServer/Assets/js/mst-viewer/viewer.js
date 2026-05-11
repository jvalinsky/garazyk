// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * MST Viewer - Main Application
 * Orchestrates the UI, API calls, and renderers
 */

import { APIClient } from '/mst-viewer/js/api-client.js';
import { TreeRenderer } from '/mst-viewer/js/tree-renderer.js';
import { ListRenderer } from '/mst-viewer/js/list-renderer.js';
import { StatsRenderer } from '/mst-viewer/js/stats-renderer.js';

class MSTViewer {
    constructor() {
        this.currentAccount = null;
        this.currentViewMode = 'tree';
        this.treeRenderer = null;
        this.listRenderer = null;
        this.statsRenderer = null;
        this.accounts = [];

        this.initializeElements();
        this.attachEventListeners();
        this.initializeRenderers();
        this.loadAccounts();
    }

    /**
     * Initialize DOM element references
     */
    initializeElements() {
        // Account list
        this.accountListEl = document.getElementById('account-list');
        this.accountSearchEl = document.getElementById('account-search');
        this.currentAccountEl = document.getElementById('current-account');
        this.loadingIndicatorEl = document.getElementById('loading-indicator');

        // View controls
        this.viewModeRadios = document.querySelectorAll('input[name="view-mode"]');

        // Export buttons
        this.exportJsonBtn = document.getElementById('export-json');
        this.exportDotBtn = document.getElementById('export-dot');
        this.exportSvgBtn = document.getElementById('export-svg');

        // Zoom buttons
        this.zoomInBtn = document.getElementById('zoom-in');
        this.zoomOutBtn = document.getElementById('zoom-out');
        this.zoomResetBtn = document.getElementById('zoom-reset');

        // Containers
        this.treeContainer = document.getElementById('tree-container');
        this.listContainer = document.getElementById('list-container');
        this.statsContainer = document.getElementById('stats-content');
    }

    /**
     * Attach event listeners
     */
    attachEventListeners() {
        // View mode radio buttons
        this.viewModeRadios.forEach(radio => {
            radio.addEventListener('change', (e) => this.handleViewModeChange(e));
        });

        // Account search
        this.accountSearchEl.addEventListener('input', (e) => this.handleAccountSearch(e));

        // Export buttons
        this.exportJsonBtn.addEventListener('click', () => this.handleExport('json'));
        this.exportDotBtn.addEventListener('click', () => this.handleExport('dot'));
        this.exportSvgBtn.addEventListener('click', () => this.handleExport('svg'));

        // Zoom buttons
        this.zoomInBtn.addEventListener('click', () => this.handleZoomIn());
        this.zoomOutBtn.addEventListener('click', () => this.handleZoomOut());
        this.zoomResetBtn.addEventListener('click', () => this.handleZoomReset());

        // Handle Escape key to clear search
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.accountSearchEl === document.activeElement) {
                this.accountSearchEl.value = '';
                this.renderAccountList();
            }
        });

        // Event delegation for account list items
        this.accountListEl.addEventListener('click', (e) => {
            const item = e.target.closest('[data-action="select-account"]');
            if (item) {
                this.selectAccount(item.dataset.did);
            }
        });
    }

    /**
     * Initialize renderers
     */
    initializeRenderers() {
        this.treeRenderer = new TreeRenderer(this.treeContainer);
        this.treeRenderer.initialize();

        this.listRenderer = new ListRenderer(this.listContainer);

        this.statsRenderer = new StatsRenderer(this.statsContainer);
    }

    /**
     * Load accounts from API
     */
    async loadAccounts() {
        try {
            this.showLoadingIndicator(true);
            const result = await APIClient.getAccounts();

            if (result.error) {
                this.showError('Failed to load accounts: ' + result.error);
                return;
            }

            this.accounts = result.accounts || [];
            this.renderAccountList();
        } catch (error) {
            this.showError('Error loading accounts: ' + error.message);
        } finally {
            this.showLoadingIndicator(false);
        }
    }

    /**
     * Render account list
     */
    renderAccountList() {
        const searchTerm = this.accountSearchEl.value.toLowerCase();
        const filteredAccounts = this.accounts.filter(account => {
            const handle = account.handle || '';
            const did = account.did || '';
            return handle.toLowerCase().includes(searchTerm) ||
                   did.toLowerCase().includes(searchTerm);
        });

        if (filteredAccounts.length === 0) {
            this.accountListEl.innerHTML = '<li class="placeholder placeholder-list-item">No accounts found</li>';
            return;
        }

        this.accountListEl.innerHTML = filteredAccounts
            .map(account => `
                <li class="account-item ${this.currentAccount === account.did ? 'active' : ''}"
                    data-action="select-account" data-did="${this.escapeHtml(account.did)}">
                    <div>${this.escapeHtml(account.handle)}</div>
                    <div class="account-item-did">${this.escapeHtml(account.did.substring(0, 30))}...</div>
                </li>
            `)
            .join('');
    }

    /**
     * Select an account
     * @param {string} did - Account DID
     */
    async selectAccount(did) {
        if (this.currentAccount === did) {
            return;
        }

        this.currentAccount = did;
        this.currentAccountEl.textContent = this.getAccountHandle(did);
        this.renderAccountList();

        await this.loadTreeAndStats();
    }

    /**
     * Get account handle by DID
     * @param {string} did - Account DID
     * @returns {string} Account handle or DID
     */
    getAccountHandle(did) {
        const account = this.accounts.find(a => a.did === did);
        return account ? account.handle : did.substring(0, 20) + '...';
    }

    /**
     * Load tree and stats for current account
     */
    async loadTreeAndStats() {
        if (!this.currentAccount) {
            return;
        }

        try {
            this.showLoadingIndicator(true);

            // Load tree and stats in parallel
            const [treeResult, statsResult] = await Promise.all([
                APIClient.getTree(this.currentAccount),
                APIClient.getStats(this.currentAccount)
            ]);

            // Render tree or list based on current view mode
            if (this.currentViewMode === 'tree') {
                this.treeRenderer.render(treeResult);
            } else {
                this.listRenderer.render(treeResult);
            }

            // Render stats
            this.statsRenderer.render(statsResult);

            // Update export buttons
            this.updateExportButtons(true);
        } catch (error) {
            this.showError('Error loading tree: ' + error.message);
        } finally {
            this.showLoadingIndicator(false);
        }
    }

    /**
     * Handle view mode change
     * @param {Event} e - Change event
     */
    handleViewModeChange(e) {
        this.currentViewMode = e.target.value;

        if (this.currentViewMode === 'tree') {
            this.treeContainer.classList.remove('hidden');
            this.listContainer.classList.add('hidden');
        } else {
            this.treeContainer.classList.add('hidden');
            this.listContainer.classList.remove('hidden');
        }

        if (this.currentAccount) {
            this.loadTreeAndStats();
        }
    }

    /**
     * Handle account search input
     * @param {Event} e - Input event
     */
    handleAccountSearch(e) {
        this.renderAccountList();
    }

    /**
     * Handle export
     * @param {string} format - Export format (json, dot, svg)
     */
    async handleExport(format) {
        if (!this.currentAccount) {
            this.showError('Please select an account first');
            return;
        }

        try {
            const btn = format === 'json' ? this.exportJsonBtn :
                       format === 'dot' ? this.exportDotBtn :
                       this.exportSvgBtn;

            btn.disabled = true;
            btn.textContent = 'Exporting...';

            await APIClient.downloadExport(this.currentAccount, format);

            btn.textContent = 'Downloaded!';
            setTimeout(() => {
                btn.textContent = format.toUpperCase();
                btn.disabled = false;
            }, 2000);
        } catch (error) {
            this.showError('Export failed: ' + error.message);
            const btn = format === 'json' ? this.exportJsonBtn :
                       format === 'dot' ? this.exportDotBtn :
                       this.exportSvgBtn;
            btn.disabled = false;
            btn.textContent = format.toUpperCase();
        }
    }

    /**
     * Handle zoom in
     */
    handleZoomIn() {
        if (this.currentViewMode === 'tree' && this.treeRenderer) {
            this.treeRenderer.zoomIn();
        }
    }

    /**
     * Handle zoom out
     */
    handleZoomOut() {
        if (this.currentViewMode === 'tree' && this.treeRenderer) {
            this.treeRenderer.zoomOut();
        }
    }

    /**
     * Handle zoom reset
     */
    handleZoomReset() {
        if (this.currentViewMode === 'tree' && this.treeRenderer) {
            this.treeRenderer.resetZoom();
        }
    }

    /**
     * Update export button states
     * @param {boolean} enabled - Whether buttons should be enabled
     */
    updateExportButtons(enabled) {
        this.exportJsonBtn.disabled = !enabled;
        this.exportDotBtn.disabled = !enabled;
        this.exportSvgBtn.disabled = !enabled;
    }

    /**
     * Show loading indicator
     * @param {boolean} show - Whether to show the indicator
     */
    showLoadingIndicator(show) {
        this.loadingIndicatorEl.classList.toggle('hidden', !show);
    }

    /**
     * Show error message
     * @param {string} message - Error message
     */
    showError(message) {
        console.error(message);
        // Could be extended to show error in UI
    }

    /**
     * Escape HTML special characters for onclick attributes
     * @param {string} str - String to escape
     * @returns {string} Escaped string
     */
    escapeHtml(str) {
        if (!str) return '';
        return str
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    /**
     * Destroy the viewer and clean up
     */
    destroy() {
        if (this.treeRenderer) {
            this.treeRenderer.destroy();
        }
        if (this.listRenderer) {
            this.listRenderer.destroy();
        }
        if (this.statsRenderer) {
            this.statsRenderer.destroy();
        }
    }
}

// Initialize viewer when DOM is ready
let viewer;
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        viewer = new MSTViewer();
    });
} else {
    viewer = new MSTViewer();
}

// Make viewer available globally for inline event handlers
window.viewer = viewer;

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (viewer) {
        viewer.destroy();
    }
});

export default viewer;
