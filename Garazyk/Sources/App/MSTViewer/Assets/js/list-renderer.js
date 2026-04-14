/**
 * List Renderer
 * Renders MST as a hierarchical list view
 */

export class ListRenderer {
    constructor(container) {
        this.container = container;
        this.data = null;
    }

    /**
     * Render the tree as a list
     * @param {Object} treeData - Tree data from API
     */
    render(treeData) {
        if (!treeData || treeData.error) {
            this.renderError(treeData?.error || 'No tree data');
            return;
        }

        this.data = treeData;
        this.container.innerHTML = this.renderNode(treeData, 0);
    }

    /**
     * Recursively render a node and its children
     * @param {Object} node - Node to render
     * @param {number} depth - Current depth in tree
     * @returns {string} HTML string
     */
    renderNode(node, depth) {
        if (!node) return '';

        let html = '';
        const indent = depth > 0 ? `style="margin-left: ${depth * 20}px;"` : '';

        // Create list item for this node
        html += `<div class="list-item" ${indent}>`;

        // Level indicator
        if (depth > 0) {
            html += `<span class="list-item-level">L${depth}</span>`;
        } else {
            html += `<span class="list-item-level" style="background-color: #3d80df; color: white;">ROOT</span>`;
        }

        // Key or label
        if (node.key) {
            html += `<strong>${this.escapeHtml(node.key.substring(0, 32))}</strong>`;
        } else if (node.cid) {
            html += `<strong>${this.escapeHtml(node.cid.substring(0, 16))}...</strong>`;
        } else {
            html += `<strong>Node</strong>`;
        }

        // CID
        if (node.cid) {
            html += `<div class="list-item-cid">${this.escapeHtml(node.cid)}</div>`;
        }

        // Node stats
        const childCount = node.children ? node.children.length : 0;
        html += `<div style="font-size: 10px; color: #666; margin-top: 4px;">`;
        html += `Children: ${childCount}`;
        if (node.value) {
            html += ` • Value: ${typeof node.value === 'string' ? node.value.substring(0, 20) : JSON.stringify(node.value).substring(0, 20)}`;
        }
        html += `</div>`;

        html += '</div>';

        // Render children
        if (node.children && node.children.length > 0) {
            for (const child of node.children) {
                html += this.renderNode(child, depth + 1);
            }
        }

        return html;
    }

    /**
     * Render error state
     * @param {string} error - Error message
     */
    renderError(error) {
        this.container.innerHTML = `
            <div class="placeholder error">
                <p>Error loading list:</p>
                <p>${this.escapeHtml(error)}</p>
            </div>
        `;
    }

    /**
     * Get statistics for the tree
     * @returns {Object} Statistics object
     */
    getStatistics() {
        if (!this.data) {
            return {
                totalNodes: 0,
                totalDepth: 0,
                leafCount: 0,
                internalCount: 0
            };
        }

        const stats = {
            totalNodes: 0,
            totalDepth: 0,
            leafCount: 0,
            internalCount: 0
        };

        const traverse = (node, depth) => {
            if (!node) return;

            stats.totalNodes++;
            stats.totalDepth = Math.max(stats.totalDepth, depth);

            if (!node.children || node.children.length === 0) {
                stats.leafCount++;
            } else {
                stats.internalCount++;
                for (const child of node.children) {
                    traverse(child, depth + 1);
                }
            }
        };

        traverse(this.data, 0);
        return stats;
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
        this.container.innerHTML = '<p class="placeholder">Select an account to view its node list.</p>';
        this.data = null;
    }

    /**
     * Destroy the renderer
     */
    destroy() {
        this.clear();
    }
}

export default ListRenderer;
