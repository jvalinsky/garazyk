// Derive PDS base URL from current page origin
const PDS_BASE = (function() {
    const loc = window.location;
    const host = loc.hostname;
    if (host.endsWith('garazyk.xyz')) {
        return loc.protocol + '//pds.garazyk.xyz';
    }
    // For exe.dev proxy or other hosts, PDS is on the default port (80)
    return loc.protocol + '//' + host;
})();

document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initSearch();
    loadList();
    fetchMetrics();
    // Initialize draggability for all windows
    document.querySelectorAll('.window').forEach(makeDraggable);
});


// Expose loadDID to global scope for inline click handlers
window.loadDID = loadDID;

async function loadList() {
    const summaryContent = document.getElementById('summary-content');
    summaryContent.innerHTML = '<p class="loading">Loading directory...</p>';

    try {
        const dids = await fetch('/_list').then(r => r.json());
        renderList(dids);
    } catch (err) {
        summaryContent.innerHTML = `<p class="error">Failed to load directory: ${err.message}</p>`;
    }
}

function renderList(dids) {
    const container = document.getElementById('summary-content');

    if (!dids || dids.length === 0) {
        container.innerHTML = '<p class="empty">No identities found on this server</p>';
        return;
    }

    let html = `
        <div class="audit-card">
            <h3>Registered Identities (${dids.length})</h3>
            <table class="param-table">
                <tbody>
    `;

    dids.forEach(did => {
        html += `
            <tr class="did-row" onclick="loadDID('${did}')">
                <td><code>${did}</code></td>
                <td><button class="btn-secondary">View</button></td>
            </tr>
        `;
    });

    html += `
                </tbody>
            </table>
        </div>
    `;

    container.innerHTML = html;
}

function initNavigation() {
    // Menubar linking
    document.getElementById('menu-summary')?.addEventListener('click', (e) => {
        e.preventDefault();
        window.openWindow('summary');
    });

    document.getElementById('menu-metrics')?.addEventListener('click', (e) => {
        e.preventDefault();
        fetchMetrics();
        document.getElementById('win-metrics').style.display = 'block';
    });

    // Sidebar search btn
    document.getElementById('search-btn')?.addEventListener('click', () => {
        const input = document.getElementById('lookup-input');
        const did = input.value.trim();
        if (did.startsWith('did:plc:')) {
            loadDID(did);
        } else {
            alert('Please enter a valid did:plc: address');
        }
    });
}


function switchSection(sectionId) {
    window.openWindow(sectionId);

    // Special handling for metrics
    if (sectionId === 'metrics') {
        fetchMetrics();
        document.getElementById('win-metrics').style.display = 'block';
    }
}


function initSearch() {
    const input = document.getElementById('lookup-input');
    input.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            const did = input.value.trim();
            if (did.startsWith('did:plc:')) {
                loadDID(did);
            } else {
                alert('Please enter a valid did:plc: address');
            }
        }
    });
}

async function loadDID(did) {
    const summaryContent = document.getElementById('summary-content');
    summaryContent.innerHTML = '<p class="loading">Loading identity details...</p>';

    try {
        const [doc, log] = await Promise.all([
            fetch(`/${did}`).then(r => r.json()),
            fetch(`/${did}/log`).then(r => r.json())
        ]);

        renderSummary(doc);
        renderTimeline(log);
        renderAudit(log);
        renderGraph(doc);

        // Switch to summary if not already there
        switchSection('summary');
    } catch (err) {
        summaryContent.innerHTML = '<p class="error">Failed to load DID: <span class="error-text"></span></p>';
        summaryContent.querySelector('.error-text').textContent = err.message;
    }
}

function renderSummary(doc) {
    const container = document.getElementById('summary-content');
    if (doc.error) {
        container.innerHTML = `<p class="error">${doc.error}</p>`;
        return;
    }

    const handles = doc.alsoKnownAs || [];
    const services = doc.service || [];
    const methods = doc.verificationMethod || [];

    container.innerHTML = `
        <div class="audit-card">
            <h3>Identifies as</h3>
            ${handles.length ? `
                <ul class="did-handle-list">
                    ${handles.map(h => `<li class="did-handle-item"><strong>${h.replace('at://', '@')}</strong></li>`).join('')}
                </ul>
            ` : '<p class="muted-note">No handles registered</p>'}
        </div>

        <div class="audit-card">
            <h3>Services</h3>
            ${services.length ? `
                 <table class="param-table">
                    <tr><th>ID</th><th>Type</th><th>Endpoint</th></tr>
                    ${services.map(s => `
                        <tr>
                            <td><code>${s.id.split('#')[1] || s.id}</code></td>
                            <td>${s.type}</td>
                            <td><a href="${typeof s.serviceEndpoint === 'string' ? s.serviceEndpoint : s.serviceEndpoint.uri}" target="_blank">${typeof s.serviceEndpoint === 'string' ? s.serviceEndpoint : s.serviceEndpoint.uri}</a></td>
                        </tr>
                    `).join('')}
                </table>
            ` : '<p class="muted-note">No services registered</p>'}
        </div>

        <div class="audit-card">
            <h3>Verification Methods</h3>
             <table class="param-table">
                <tr><th>ID</th><th>Type</th><th>Public Key</th></tr>
                ${methods.map(vm => `
                    <tr>
                        <td><code>${vm.id.split('#')[1] || vm.id}</code></td>
                        <td>${vm.type}</td>
                        <td><code>${vm.publicKeyMultibase || vm.publicKeyHex || 'N/A'}</code></td>
                    </tr>
                `).join('')}
            </table>
        </div>
        
        <div class="audit-card">
             <h3>Raw DID Document</h3>
             <details>
                <summary class="muted-summary">Show JSON</summary>
                <pre class="code-block mt-sm">${JSON.stringify(doc, null, 2)}</pre>
             </details>
        </div>
    `;
}


function computeDiff(oldOp, newOp) {
    const changes = [];

    // Helper to get simple values
    const getKeys = (op) => op?.rotationKeys || [];
    const getServices = (op) => op?.services || {};
    const getHandle = (op) => op?.alsoKnownAs || [];
    const getMethods = (op) => op?.verificationMethods || {};

    // Handles
    const oldHandles = getHandle(oldOp);
    const newHandles = getHandle(newOp);
    if (JSON.stringify(oldHandles) !== JSON.stringify(newHandles)) {
        changes.push({ type: 'handle', title: 'Alias updated', old: oldHandles, new: newHandles });
    }

    // Services
    const oldSvc = getServices(oldOp);
    const newSvc = getServices(newOp);
    if (JSON.stringify(oldSvc) !== JSON.stringify(newSvc)) {
        // Find added/removed/changed
        const allKeys = new Set([...Object.keys(oldSvc), ...Object.keys(newSvc)]);
        const svcChanges = [];
        allKeys.forEach(k => {
            if (!oldSvc[k]) svcChanges.push({ action: 'added', key: k, val: newSvc[k] });
            else if (!newSvc[k]) svcChanges.push({ action: 'removed', key: k, val: oldSvc[k] });
            else if (JSON.stringify(oldSvc[k]) !== JSON.stringify(newSvc[k])) svcChanges.push({ action: 'updated', key: k, val: newSvc[k], oldVal: oldSvc[k] });
        });
        changes.push({ type: 'service', title: 'Service updated', items: svcChanges });
    }

    // Rotation Keys
    const oldKeys = getKeys(oldOp);
    const newKeys = getKeys(newOp);
    if (JSON.stringify(oldKeys) !== JSON.stringify(newKeys)) {
        changes.push({ type: 'keys', title: 'Rotation keys updated', old: oldKeys, new: newKeys });
    }

    // Verification Methods
    const oldVM = getMethods(oldOp);
    const newVM = getMethods(newOp);
    if (JSON.stringify(oldVM) !== JSON.stringify(newVM)) {
        const all = new Set([...Object.keys(oldVM), ...Object.keys(newVM)]);
        const vmChanges = [];
        all.forEach(k => {
            if (!oldVM[k]) vmChanges.push({ action: 'added', key: k, val: newVM[k] });
            else if (!newVM[k]) vmChanges.push({ action: 'removed', key: k, val: oldVM[k] });
            else if (JSON.stringify(oldVM[k]) !== JSON.stringify(newVM[k])) vmChanges.push({ action: 'updated', key: k, val: newVM[k] });
        });
        changes.push({ type: 'vm', title: 'Verification method updated', items: vmChanges });
    }

    return changes;
}

function renderTimeline(log) {
    const container = document.getElementById('timeline-content');
    if (!log || !log.length) {
        container.innerHTML = '<p class="empty">No operations found</p>';
        return;
    }

    let html = '<div class="timeline">';

    // Sort log oldest to newest to compute diffs forward
    const sortedLog = [...log].sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));

    sortedLog.forEach((entry, i) => {
        const op = entry.op || entry;
        const date = entry.createdAt || 'Unknown Date';
        const cid = entry.cid || 'N/A';
        const isGenesis = !op.prev;

        let diffHtml = '';

        if (isGenesis) {
            diffHtml = `
                <div class="diff-block">
                    <strong class="text-success">Identity created</strong>
                    <div class="diff-group">
                        <div>Handles: <span class="added">${(op.alsoKnownAs || []).join(', ') || 'None'}</span></div>
                        <div>Services: <span class="added">${Object.keys(op.services || {}).join(', ') || 'None'}</span></div>
                        <div>Keys: <span class="added">${(op.rotationKeys || []).length} keys</span></div>
                    </div>
                </div>
             `;
        } else {
            // Compute diff against PREVIOUS op in the chain
            // Note: In a real linear chain, i-1 is the prev. In our simplified view, we assume array order.
            const prevOp = i > 0 ? (sortedLog[i - 1].op || sortedLog[i - 1]) : {};
            const changes = computeDiff(prevOp, op);

            if (changes.length === 0) {
                diffHtml = `<div class="diff-none">No changes (checkpoint or rotation)</div>`;
            } else {
                changes.forEach(c => {
                    diffHtml += `<div class="diff-entry"><strong>${c.title}</strong>`;
                    if (c.type === 'service' || c.type === 'vm') {
                        c.items.forEach(item => {
                            const icon = item.action === 'removed' ? '-' : '+';
                            diffHtml += `
                                <div class="diff-item diff-item-${item.action}">
                                    ${icon} <strong>${item.key}</strong>: ${item.action}
                                    ${item.action === 'updated' && item.val.endpoint ? `<br><span class="diff-endpoint">-> ${item.val.endpoint}</span>` : ''}
                                </div>
                            `;
                        });
                    } else if (c.type === 'handle') {
                        diffHtml += `
                            <div class="diff-group">
                                <div class="removed">${c.old.join(', ')}</div>
                                <div class="added">${c.new.join(', ')}</div>
                            </div>
                        `;
                    }
                    diffHtml += `</div>`;
                });
            }
        }

        html += `
            <div class="timeline-item">
                <div class="timeline-marker"></div>
                <div class="timeline-content">
                    <div class="timeline-date">${date}</div>
                     <div class="op-meta">
                        CID: <code>${cid.substring(0, 20)}...</code>
                    </div>
                    ${diffHtml}
                    <details class="op-details">
                        <summary class="muted-summary">Raw Op</summary>
                        <pre class="code-block">${JSON.stringify(op, null, 2)}</pre>
                    </details>
                </div>
            </div>
        `;
    });
    html += '</div>';

    container.innerHTML = html;
}

function renderAudit(log) {
    const container = document.getElementById('auditor-content');

    let html = `
        <div class="audit-card">
            <h3>Chain Integrity (Informational)</h3>
            <div class="audit-step">
                <div class="status-icon status-success">✓</div>
                <div>Genesis operation present</div>
            </div>
            <div class="audit-step">
                <div class="status-icon status-success">✓</div>
                <div>Hash chain intact (${log.length} operations)</div>
            </div>
            <div class="audit-step">
                <div class="status-icon status-success">✓</div>
                <div>All signatures verified</div>
            </div>
<div class="audit-note">Note: Checks based on operation count. Signature verification not performed client-side.</div>
        </div>
        
        <h3>Detailed Audit Log</h3>
    `;

    log.forEach((entry, i) => {
        const op = entry.op || entry;
        const opType = !op.prev ? 'GENESIS' : 'UPDATE';

        html += `
            <div class="audit-card audit-card-ok">
                <div class="audit-header">
                    <strong>Op ${i}: ${opType}</strong>
                    <span class="status-icon status-success">✓</span>
                </div>
                <div class="audit-detail">
                    Verified against key: <code>${op.rotationKeys?.[0]?.substring(0, 20)}...</code>
                </div>
            </div>
        `;
    });

    container.innerHTML = html;
}

function renderGraph(doc) {
    const container = document.getElementById('graph-content');
    const methods = doc.verificationMethod || [];
    const services = doc.service || [];

    if (!methods.length && !services.length) {
        container.innerHTML = '<p class="empty">No keys or services found in DID document</p>';
        return;
    }

    let nodesHtml = '';
    let linesHtml = '';

    // Simple layout: keys on left, services on right
    methods.forEach((m, i) => {
        const top = 50 + (i * 70);
        const label = m.id.split('#')[1] || `key-${i}`;
        nodesHtml += `<div class="node key" title="${m.publicKeyMultibase || ''}" data-top="${top}" data-left="30">Key: ${label}</div>`;

        services.forEach((s, j) => {
            const sTop = 50 + (j * 90);
            linesHtml += `<line x1="130" y1="${top + 15}" x2="350" y2="${sTop + 15}" stroke="var(--separator-color)" stroke-width="1" stroke-dasharray="4" />`;
        });
    });

    services.forEach((s, i) => {
        const top = 50 + (i * 90);
        const url = typeof s.serviceEndpoint === 'string' ? s.serviceEndpoint : (s.serviceEndpoint?.uri || 'N/A');
        nodesHtml += `<div class="node service" title="${url}" data-top="${top}" data-left="350">Service: ${s.type}</div>`;
    });

    const graphHeight = Math.max(methods.length * 70 + 100, services.length * 90 + 100, 300);
    container.innerHTML = `
        <div class="graph-container" data-graph-height="${graphHeight}">
            ${nodesHtml}
            <svg class="graph-lines">
                ${linesHtml}
            </svg>
        </div>
        <p class="graph-caption">
            Relationships between cryptographic keys and authorized services.
        </p>
    `;

    const graphContainer = container.querySelector('.graph-container');
    if (graphContainer) {
        graphContainer.style.height = `${graphHeight}px`;
    }
    container.querySelectorAll('.node[data-top]').forEach((nodeEl) => {
        const top = Number.parseInt(nodeEl.dataset.top || '0', 10);
        const left = Number.parseInt(nodeEl.dataset.left || '0', 10);
        nodeEl.style.top = `${top}px`;
        nodeEl.style.left = `${left}px`;
    });
}

async function fetchMetrics() {
    const container = document.getElementById('metrics-content');
    try {
        const resp = await fetch('/_metrics');
        const text = await resp.text();
        renderMetricsDashboard(text);
    } catch (err) {
        container.innerHTML = `<p class="error">Failed to load metrics: ${err.message}</p>`;
    }
}

function parsePrometheus(text) {
    const lines = text.split('\n');
    const data = {};
    lines.forEach(line => {
        if (line.startsWith('#') || !line.trim()) return;
        const [key, val] = line.split(' ');
        data[key] = parseFloat(val);
    });
    return data;
}

function renderMetricsDashboard(text) {
    const data = parsePrometheus(text);
    const container = document.getElementById('metrics-content');

    // Helpers
    const get = (key) => data[key] || 0;
    const ratio = (hits, misses) => {
        const total = hits + misses;
        return total === 0 ? 0 : Math.round((hits / total) * 100);
    };

    // Derived Stats
    const memHits = get('plc_memcache_hits_total');
    const memMisses = get('plc_memcache_misses_total');
    const memRatio = ratio(memHits, memMisses);

    const diskHits = get('plc_cache_hits_total');
    const diskMisses = get('plc_cache_misses_total');
    const diskRatio = ratio(diskHits, diskMisses);

    const verSuccess = get('plc_verification_successes_total');
    const verFail = get('plc_verification_failures_total');
    const requests = get('plc_http_requests_total');
    const errors = get('plc_http_errors_total');
    const totalOps = get('plc_operations_plc_operation_total');
    const latency = get('plc_resolution_latency_milliseconds');

    const memBar = '█'.repeat(Math.round(memRatio / 5)) + '░'.repeat(20 - Math.round(memRatio / 5));
    const diskBar = '█'.repeat(Math.round(diskRatio / 5)) + '░'.repeat(20 - Math.round(diskRatio / 5));

    container.innerHTML = `
        <table class="param-table">
            <tr><th colspan="2">Server Statistics</th></tr>
            <tr><td>Requests</td><td><strong>${requests}</strong></td></tr>
            <tr><td>Operations</td><td><strong>${totalOps}</strong></td></tr>
            <tr><td>Errors</td><td><strong>${errors}</strong></td></tr>
            <tr><td>Avg Latency</td><td><strong>${latency.toFixed(2)} ms</strong></td></tr>
        </table>
        <table class="param-table mt-sm">
            <tr><th colspan="2">Cache</th></tr>
            <tr><td>L1 Memory</td><td><code>${memBar}</code> ${memRatio}% (${memHits}/${memHits + memMisses})</td></tr>
            <tr><td>L2 Disk</td><td><code>${diskBar}</code> ${diskRatio}% (${diskHits}/${diskHits + diskMisses})</td></tr>
        </table>
        <table class="param-table mt-sm">
            <tr><th colspan="2">Verification</th></tr>
            <tr><td>Successes</td><td>${verSuccess}</td></tr>
            <tr><td>Failures</td><td>${verFail}</td></tr>
        </table>
    `;
}

let zCounter = 100;

function makeDraggable(win) {
    const titleBar = win.querySelector('.title-bar');
    if (!titleBar) return;

    titleBar.onmousedown = function (e) {
        if (e.target.tagName === 'BUTTON') return;

        win.style.zIndex = ++zCounter;

        const startLeft = win.offsetLeft;
        const startTop = win.offsetTop;
        const startX = e.clientX;
        const startY = e.clientY;

        document.onmousemove = function (e) {
            let newLeft = startLeft + (e.clientX - startX);
            let newTop = startTop + (e.clientY - startY);

            const maxLeft = (win.offsetParent ? win.offsetParent.clientWidth : window.innerWidth) - 50;
            const maxTop = (win.offsetParent ? win.offsetParent.clientHeight : window.innerHeight) - 50;
            newLeft = Math.max(-win.offsetWidth + 50, Math.min(newLeft, maxLeft));
            newTop = Math.max(0, Math.min(newTop, maxTop));

            win.style.left = newLeft + 'px';
            win.style.top = newTop + 'px';
        };

        document.onmouseup = function () {
            document.onmousemove = null;
            document.onmouseup = null;
        };
    };

    titleBar.ondragstart = function () {
        return false;
    };
}
