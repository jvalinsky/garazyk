/**
 * Tree Renderer
 * Uses D3.js to visualize MST as a hierarchical tree diagram
 */

const d3 = window.d3;

export class TreeRenderer {
    constructor(container) {
        this.container = container;
        this.svg = null;
        this.g = null;
        this.zoom = d3.zoom();
        this.currentTransform = d3.zoomIdentity;
        this.data = null;
        this.width = 0;
        this.height = 0;
        this.nodeTooltip = null;
    }

    /**
     * Initialize the tree renderer
     */
    initialize() {
        // Clear existing content
        this.container.innerHTML = '';

        // Get dimensions
        this.width = this.container.clientWidth;
        this.height = this.container.clientHeight;

        // Create SVG
        this.svg = d3.select(this.container)
            .append('svg')
            .attr('width', this.width)
            .attr('height', this.height)
            .attr('class', 'mst-tree');

        // Create group for zooming/panning
        this.g = this.svg.append('g');

        // Setup zoom behavior
        this.zoom.on('zoom', (event) => {
            this.currentTransform = event.transform;
            this.g.attr('transform', event.transform);
        });

        this.svg.call(this.zoom);

        // Create tooltip
        this.nodeTooltip = document.createElement('div');
        this.nodeTooltip.className = 'node-tooltip';
        this.nodeTooltip.style.display = 'none';
        document.body.appendChild(this.nodeTooltip);

        // Handle window resize
        window.addEventListener('resize', () => this.handleResize());
    }

    /**
     * Render the tree with given data
     * @param {Object} treeData - Tree data from API
     */
    render(treeData) {
        if (!treeData || treeData.error) {
            this.renderError(treeData?.error || 'No tree data');
            return;
        }

        this.data = treeData;

        // Convert API data to D3 hierarchy
        const root = d3.hierarchy(this.data, d => d.children || []);

        // Calculate tree layout
        const tree = d3.tree().size([this.width, this.height]);
        tree(root);

        // Remove old content
        this.g.selectAll('*').remove();

        // Draw links first (so they appear behind nodes)
        const links = this.g.selectAll('.link')
            .data(root.links())
            .enter()
            .append('path')
            .attr('class', 'link')
            .attr('d', d3.linkVertical()
                .x(d => d.x)
                .y(d => d.y));

        // Draw nodes
        const nodes = this.g.selectAll('.node-group')
            .data(root.descendants())
            .enter()
            .append('g')
            .attr('class', 'node-group')
            .attr('transform', d => `translate(${d.x},${d.y})`);

        // Add circles for nodes
        nodes.append('circle')
            .attr('class', d => {
                let classes = 'node-circle';
                if (d === root) classes += ' root';
                if (!d.children || d.children.length === 0) classes += ' leaf';
                return classes;
            })
            .attr('r', d => this.getNodeRadius(d))
            .on('mouseover', (event, d) => this.showNodeTooltip(event, d))
            .on('mouseout', () => this.hideNodeTooltip())
            .on('click', (event, d) => this.onNodeClick(event, d));

        // Add labels
        nodes.append('text')
            .attr('class', 'node-label')
            .attr('text-anchor', 'middle')
            .attr('dy', '0.31em')
            .text(d => this.getNodeLabel(d))
            .style('pointer-events', 'none');

        // Set initial zoom to fit
        this.fitToScreen();
    }

    /**
     * Render error state
     * @param {string} error - Error message
     */
    renderError(error) {
        this.container.innerHTML = `
            <div class="placeholder error">
                <p>Error loading tree:</p>
                <p>${this.escapeHtml(error)}</p>
            </div>
        `;
    }

    /**
     * Get radius for a node based on its properties
     * @param {Object} d - D3 node data
     * @returns {number} Radius in pixels
     */
    getNodeRadius(d) {
        if (d.depth === 0) return 8;  // Root
        if (!d.children || d.children.length === 0) return 4;  // Leaf
        return 6;  // Internal
    }

    /**
     * Get display label for a node
     * @param {Object} d - D3 node data
     * @returns {string} Label text
     */
    getNodeLabel(d) {
        const data = d.data;
        if (data.key) {
            return data.key.substring(0, 8);
        }
        if (data.cid) {
            return data.cid.substring(0, 8);
        }
        return `L${d.depth}`;
    }

    /**
     * Show tooltip for a node
     * @param {Event} event - Mouse event
     * @param {Object} d - D3 node data
     */
    showNodeTooltip(event, d) {
        const data = d.data;
        let content = '';

        if (data.key) {
            content += `<div class="node-tooltip-label">Key</div>`;
            content += `<div class="node-tooltip-content">${this.escapeHtml(data.key)}</div>`;
        }

        if (data.cid) {
            content += `<div style="margin-top: 6px;"><div class="node-tooltip-label">CID</div>`;
            content += `<div class="node-tooltip-content">${this.escapeHtml(data.cid)}</div></div>`;
        }

        if (data.value) {
            content += `<div style="margin-top: 6px;"><div class="node-tooltip-label">Value</div>`;
            content += `<div class="node-tooltip-content">${this.escapeHtml(JSON.stringify(data.value))}</div></div>`;
        }

        content += `<div style="margin-top: 6px; font-size: 10px; color: #666;">Depth: ${d.depth} | Children: ${d.children ? d.children.length : 0}</div>`;

        this.nodeTooltip.innerHTML = content;
        this.nodeTooltip.style.display = 'block';
        this.nodeTooltip.style.left = (event.pageX + 10) + 'px';
        this.nodeTooltip.style.top = (event.pageY + 10) + 'px';
    }

    /**
     * Hide tooltip
     */
    hideNodeTooltip() {
        this.nodeTooltip.style.display = 'none';
    }

    /**
     * Handle node click
     * @param {Event} event - Click event
     * @param {Object} d - D3 node data
     */
    onNodeClick(event, d) {
        event.stopPropagation();
        // Can be extended for node selection, details panel, etc.
    }

    /**
     * Fit the tree to the screen
     */
    fitToScreen() {
        if (!this.svg) return;

        const bounds = this.g.node().getBBox();
        const fullWidth = bounds.width;
        const fullHeight = bounds.height;

        const midX = bounds.x + fullWidth / 2;
        const midY = bounds.y + fullHeight / 2;

        if (fullWidth === 0 || fullHeight === 0) return;

        const scale = 0.85 / Math.max(
            fullWidth / this.width,
            fullHeight / this.height
        );

        const translate = [
            this.width / 2 - scale * midX,
            this.height / 2 - scale * midY
        ];

        this.svg.transition()
            .duration(750)
            .call(this.zoom.transform,
                d3.zoomIdentity
                    .translate(translate[0], translate[1])
                    .scale(scale)
            );
    }

    /**
     * Zoom in
     */
    zoomIn() {
        this.svg.transition()
            .duration(300)
            .call(this.zoom.scaleBy, 1.3);
    }

    /**
     * Zoom out
     */
    zoomOut() {
        this.svg.transition()
            .duration(300)
            .call(this.zoom.scaleBy, 1 / 1.3);
    }

    /**
     * Reset zoom and pan
     */
    resetZoom() {
        this.fitToScreen();
    }

    /**
     * Handle window resize
     */
    handleResize() {
        const newWidth = this.container.clientWidth;
        const newHeight = this.container.clientHeight;

        if (newWidth === this.width && newHeight === this.height) {
            return;
        }

        this.width = newWidth;
        this.height = newHeight;

        if (this.svg) {
            this.svg
                .attr('width', this.width)
                .attr('height', this.height);

            if (this.data) {
                this.render(this.data);
            }
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
     * Destroy the renderer and clean up
     */
    destroy() {
        if (this.nodeTooltip && this.nodeTooltip.parentNode) {
            document.body.removeChild(this.nodeTooltip);
        }
        if (this.svg) {
            this.svg.remove();
        }
        window.removeEventListener('resize', () => this.handleResize());
    }
}

export default TreeRenderer;
