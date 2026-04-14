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

function setStatus(text) {
    var el = document.getElementById('mst-status-left');
    if (el) el.textContent = text;
}

async function loadMST(did) {
    const container = document.getElementById('mst-tree-container');
    const statsEl = document.getElementById('mst-stats');

    container.innerHTML = '<p class="loading" style="padding: 20px;">Loading\u2026</p>';
    statsEl.textContent = '';
    setStatus('Loading\u2026');

    try {
        const [treeResp, statsResp] = await Promise.all([
            fetch('/api/mst/tree/' + encodeURIComponent(did)),
            fetch('/api/mst/stats/' + encodeURIComponent(did))
        ]);

        if (!treeResp.ok) {
            throw new Error('HTTP ' + treeResp.status + ': ' + treeResp.statusText);
        }

        const treeData = await treeResp.json();
        currentMstData = treeData;

        if (treeData.error) {
            container.innerHTML = '<p class="placeholder" style="padding: 20px;">' + escapeHtml(treeData.error) + '</p>';
            setStatus('Error');
            return;
        }

        var stats = null;
        if (statsResp.ok) {
            stats = await statsResp.json();
            if (stats.error) stats = null;
        }

        renderMST(treeData);
        updateStats(treeData, stats);

        var nodeCount = (stats && stats.nodeCount) || treeData.nodeCount || 0;
        var entryCount = (stats && stats.entryCount) || treeData.entryCount || 0;
        setStatus(nodeCount + ' nodes, ' + entryCount + ' entries');
    } catch (e) {
        container.innerHTML = '<p class="placeholder" style="padding: 20px;">Error: ' + escapeHtml(e.message) + '</p>';
        setStatus('Error: ' + e.message);
    }
}

function updateStats(treeData, stats) {
    const statsEl = document.getElementById('mst-stats');
    var nodeCount = (stats && stats.nodeCount) || treeData.nodeCount || 0;
    var entryCount = (stats && stats.entryCount) || treeData.entryCount || 0;
    var maxDepth = (stats && stats.maxDepth) || treeData.maxDepth || 0;

    var parts = [];
    parts.push('Nodes: ' + nodeCount);
    parts.push('Entries: ' + entryCount);
    parts.push('Depth: ' + maxDepth);

    if (stats && stats.leafNodeCount !== undefined) {
        parts.push('Leaves: ' + stats.leafNodeCount);
    }

    statsEl.textContent = parts.join(' \u2502 ');
}

function buildHierarchy(flatData) {
    if (!flatData || !flatData.nodes || !flatData.rootCID) return null;

    var nodeMap = new Map();
    flatData.nodes.forEach(function(n) {
        if (n.cid) nodeMap.set(n.cid, n);
    });

    var visited = new Set();

    function build(cid, depth) {
        if (!cid || visited.has(cid) || depth > 64) return null;
        visited.add(cid);

        var node = nodeMap.get(cid);
        if (!node) return null;

        var result = {
            cid: node.cid,
            type: node.kind || (node.level === 0 ? 'leaf' : 'non-leaf'),
            level: node.level || 0,
            children: []
        };

        if (node.left) {
            var leftChild = build(node.left, depth + 1);
            if (leftChild) {
                leftChild._label = '\u2190 subtree';
                result.children.push(leftChild);
            }
        }

        if (node.entries) {
            node.entries.forEach(function(entry) {
                result.children.push({
                    type: 'entry',
                    key: entry.fullKey || '',
                    value: entry.value || '',
                    children: []
                });

                if (entry.tree) {
                    var subtree = build(entry.tree, depth + 1);
                    if (subtree) {
                        subtree._label = '\u2192 subtree';
                        result.children.push(subtree);
                    }
                }
            });
        }

        return result;
    }

    return build(flatData.rootCID, 0);
}

function renderMST(data) {
    const container = document.getElementById('mst-tree-container');

    var root = buildHierarchy(data);
    if (!root) {
        container.innerHTML = '<p class="placeholder" style="padding: 20px;">Empty MST.</p>';
        return;
    }

    var treeEl = document.createElement('div');
    treeEl.className = 'mst-tree';
    treeEl.appendChild(renderNode(root, 0, true));
    container.innerHTML = '';
    container.appendChild(treeEl);
}

function renderNode(node, depth, startOpen) {
    var wrapper = document.createElement('div');
    wrapper.className = 'mst-node-wrapper';
    wrapper.style.marginLeft = (depth * 14) + 'px';

    var header = document.createElement('div');
    header.className = 'mst-node-header';

    // Entry node (record key)
    if (node.type === 'entry') {
        var spacer = document.createElement('span');
        spacer.style.width = '12px';
        spacer.style.display = 'inline-block';
        header.appendChild(spacer);

        var icon = document.createElement('span');
        icon.className = 'mst-icon';
        icon.textContent = '\u25AB';
        header.appendChild(icon);

        var keyEl = document.createElement('span');
        keyEl.className = 'mst-key-entry';
        keyEl.textContent = truncateKey(node.key);
        keyEl.title = node.key;
        header.appendChild(keyEl);

        if (node.value) {
            var arrow = document.createElement('span');
            arrow.className = 'mst-cid';
            arrow.textContent = ' \u2192 ';
            header.appendChild(arrow);

            var valEl = document.createElement('span');
            valEl.className = 'mst-cid';
            valEl.textContent = truncateCid(node.value);
            valEl.title = node.value;
            header.appendChild(valEl);
        }

        wrapper.appendChild(header);
        return wrapper;
    }

    // MST tree node
    var hasChildren = node.children && node.children.length > 0;

    if (hasChildren) {
        var toggle = document.createElement('span');
        toggle.className = 'mst-toggle';
        toggle.textContent = startOpen ? '\u25BC' : '\u25B6';
        toggle.style.cursor = 'pointer';
        toggle.addEventListener('click', function() {
            var content = wrapper.querySelector('.mst-node-children');
            if (content.style.display === 'none') {
                content.style.display = 'block';
                toggle.textContent = '\u25BC';
            } else {
                content.style.display = 'none';
                toggle.textContent = '\u25B6';
            }
        });
        header.appendChild(toggle);
    } else {
        var spacer2 = document.createElement('span');
        spacer2.style.width = '12px';
        spacer2.style.display = 'inline-block';
        header.appendChild(spacer2);
    }

    var icon2 = document.createElement('span');
    icon2.className = 'mst-icon';
    icon2.textContent = node.type === 'leaf' ? '\u25A1' : '\u25A0';
    header.appendChild(icon2);

    var labelEl = document.createElement('span');
    labelEl.className = 'mst-key';
    labelEl.textContent = node._label || ('L' + node.level);
    header.appendChild(labelEl);

    if (node.cid) {
        var cidEl = document.createElement('span');
        cidEl.className = 'mst-cid';
        cidEl.textContent = ' ' + truncateCid(node.cid);
        cidEl.title = node.cid;
        header.appendChild(cidEl);
    }

    wrapper.appendChild(header);

    if (hasChildren) {
        var childrenEl = document.createElement('div');
        childrenEl.className = 'mst-node-children';
        if (!startOpen) childrenEl.style.display = 'none';
        for (var i = 0; i < node.children.length; i++) {
            childrenEl.appendChild(renderNode(node.children[i], depth + 1, false));
        }
        wrapper.appendChild(childrenEl);
    }

    return wrapper;
}

function truncateKey(key) {
    if (key.length <= 44) return key;
    return key.substring(0, 41) + '\u2026';
}

function truncateCid(cid) {
    if (!cid) return '';
    if (cid.length <= 16) return cid;
    return cid.substring(0, 8) + '\u2026' + cid.substring(cid.length - 4);
}

function expandAll() {
    document.querySelectorAll('#mst-tree-container .mst-node-children').forEach(function(el) {
        el.style.display = 'block';
    });
    document.querySelectorAll('#mst-tree-container .mst-toggle').forEach(function(el) {
        el.textContent = '\u25BC';
    });
    setStatus('All nodes expanded');
}

function collapseAll() {
    document.querySelectorAll('#mst-tree-container .mst-node-children').forEach(function(el) {
        el.style.display = 'none';
    });
    document.querySelectorAll('#mst-tree-container .mst-toggle').forEach(function(el) {
        el.textContent = '\u25B6';
    });
    setStatus('All nodes collapsed');
}

function exportJSON() {
    if (!currentMstData) {
        alert('No MST data to export.');
        return;
    }
    var json = JSON.stringify(currentMstData, null, 2);
    var blob = new Blob([json], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'mst-export.json';
    a.click();
    URL.revokeObjectURL(url);
    setStatus('Exported JSON');
}

function setDID(did) {
    var input = document.getElementById('mst-did-input');
    if (input && did) input.value = did;
}

function init() {
    var loadBtn = document.getElementById('mst-load-btn');
    var didInput = document.getElementById('mst-did-input');
    var expandBtn = document.getElementById('mst-expand-all');
    var collapseBtn = document.getElementById('mst-collapse-all');
    var exportBtn = document.getElementById('mst-export-json');

    if (loadBtn) {
        loadBtn.addEventListener('click', function() {
            var did = didInput.value.trim();
            if (did) loadMST(did);
        });
    }

    if (didInput) {
        didInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                var did = didInput.value.trim();
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
    loadMST: loadMST,
    setDID: setDID
};

export { MSTViewer };
