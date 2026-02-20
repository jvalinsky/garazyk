let currentMstData = null;

function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

async function loadMST(did) {
    const container = document.getElementById('mst-tree-container');
    const statsEl = document.getElementById('mst-stats');
    
    container.innerHTML = '<p class="loading" style="padding: 20px;">Loading MST...</p>';
    statsEl.textContent = '';

    try {
        const resp = await fetch('/api/mst/tree?did=' + encodeURIComponent(did));
        if (!resp.ok) {
            throw new Error('HTTP ' + resp.status + ': ' + resp.statusText);
        }
        const data = await resp.json();
        currentMstData = data;
        
        if (data.error) {
            container.innerHTML = '<p class="error" style="padding: 20px; color: #cc0000;">' + escapeHtml(data.error) + '</p>';
            return;
        }

        renderMST(data);
        updateStats(data);
    } catch (e) {
        container.innerHTML = '<p class="error" style="padding: 20px; color: #cc0000;">Error: ' + escapeHtml(e.message) + '</p>';
    }
}

function updateStats(data) {
    const statsEl = document.getElementById('mst-stats');
    if (!data || !data.stats) {
        statsEl.textContent = '';
        return;
    }
    const s = data.stats;
    statsEl.innerHTML = 'Nodes: <strong>' + (s.nodeCount || 0) + '</strong> | ' +
        'Leaves: <strong>' + (s.leafCount || 0) + '</strong> | ' +
        'Depth: <strong>' + (s.maxDepth || 0) + '</strong>';
}

function renderMST(data) {
    const container = document.getElementById('mst-tree-container');
    
    if (!data || !data.root) {
        container.innerHTML = '<p class="placeholder" style="padding: 20px;">No MST data available.</p>';
        return;
    }

    const treeEl = document.createElement('div');
    treeEl.className = 'mst-tree';
    treeEl.appendChild(renderNode(data.root, 0));
    container.innerHTML = '';
    container.appendChild(treeEl);
}

function renderNode(node, depth) {
    const wrapper = document.createElement('div');
    wrapper.className = 'mst-node-wrapper';
    wrapper.style.marginLeft = (depth * 16) + 'px';

    const header = document.createElement('div');
    header.className = 'mst-node-header';

    if (node.children && node.children.length > 0) {
        const toggle = document.createElement('span');
        toggle.className = 'mst-toggle';
        toggle.innerHTML = '\u25B6';
        toggle.style.cursor = 'pointer';
        toggle.style.marginRight = '4px';
        toggle.addEventListener('click', function() {
            const content = wrapper.querySelector('.mst-node-children');
            if (content.style.display === 'none') {
                content.style.display = 'block';
                toggle.innerHTML = '\u25BC';
            } else {
                content.style.display = 'none';
                toggle.innerHTML = '\u25B6';
            }
        });
        header.appendChild(toggle);
    } else {
        const spacer = document.createElement('span');
        spacer.innerHTML = '&nbsp;&nbsp;&nbsp;';
        header.appendChild(spacer);
    }

    const icon = document.createElement('span');
    icon.className = 'mst-icon';
    icon.textContent = node.type === 'leaf' ? '\uD83D\uDCC4' : '\uD83D\uDCC1';
    icon.style.marginRight = '4px';
    header.appendChild(icon);

    if (node.key !== undefined && node.key !== null) {
        const keyEl = document.createElement('span');
        keyEl.className = 'mst-key';
        keyEl.textContent = truncateKey(String(node.key));
        keyEl.title = node.key;
        header.appendChild(keyEl);
    }

    if (node.cid) {
        const cidEl = document.createElement('span');
        cidEl.className = 'mst-cid';
        cidEl.textContent = truncateCid(node.cid);
        cidEl.title = node.cid;
        cidEl.style.marginLeft = '8px';
        cidEl.style.color = '#666';
        cidEl.style.fontSize = '10px';
        header.appendChild(cidEl);
    }

    wrapper.appendChild(header);

    if (node.children && node.children.length > 0) {
        const childrenEl = document.createElement('div');
        childrenEl.className = 'mst-node-children';
        for (const child of node.children) {
            childrenEl.appendChild(renderNode(child, depth + 1));
        }
        wrapper.appendChild(childrenEl);
    }

    return wrapper;
}

function truncateKey(key) {
    if (key.length <= 40) return key;
    return key.substring(0, 37) + '...';
}

function truncateCid(cid) {
    if (!cid) return '';
    if (cid.length <= 16) return cid;
    return cid.substring(0, 8) + '...' + cid.substring(cid.length - 4);
}

function expandAll() {
    document.querySelectorAll('#mst-tree-container .mst-node-children').forEach(function(el) {
        el.style.display = 'block';
    });
    document.querySelectorAll('#mst-tree-container .mst-toggle').forEach(function(el) {
        el.innerHTML = '\u25BC';
    });
}

function collapseAll() {
    document.querySelectorAll('#mst-tree-container .mst-node-children').forEach(function(el) {
        el.style.display = 'none';
    });
    document.querySelectorAll('#mst-tree-container .mst-toggle').forEach(function(el) {
        el.innerHTML = '\u25B6';
    });
}

function exportJSON() {
    if (!currentMstData) {
        alert('No MST data to export.');
        return;
    }
    const json = JSON.stringify(currentMstData, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'mst-export.json';
    a.click();
    URL.revokeObjectURL(url);
}

function init() {
    const loadBtn = document.getElementById('mst-load-btn');
    const didInput = document.getElementById('mst-did-input');
    const expandBtn = document.getElementById('mst-expand-all');
    const collapseBtn = document.getElementById('mst-collapse-all');
    const exportBtn = document.getElementById('mst-export-json');

    if (loadBtn) {
        loadBtn.addEventListener('click', function() {
            const did = didInput.value.trim();
            if (did) loadMST(did);
        });
    }

    if (didInput) {
        didInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                const did = didInput.value.trim();
                if (did) loadMST(did);
            }
        });
    }

    if (expandBtn) expandBtn.addEventListener('click', expandAll);
    if (collapseBtn) collapseBtn.addEventListener('click', collapseAll);
    if (exportBtn) exportBtn.addEventListener('click', exportJSON);
}

const MSTViewer = {
    init: init,
    loadMST: loadMST
};

export { MSTViewer };
