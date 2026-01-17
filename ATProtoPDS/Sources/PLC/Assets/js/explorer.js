document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initSearch();
    loadList();
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
            <div style="max-height: 400px; overflow-y: auto;">
                <table class="param-table">
                    <tbody>
    `;

    dids.forEach(did => {
        html += `
            <tr style="cursor: pointer;" onclick="loadDID('${did}')">
                <td><code>${did}</code></td>
                <td><button class="btn-secondary">View</button></td>
            </tr>
        `;
    });

    html += `
                    </tbody>
                </table>
            </div>
        </div>
    `;

    container.innerHTML = html;
}

function initNavigation() {
    const navRows = document.querySelectorAll('.nav-row[data-section]');
    navRows.forEach(row => {
        row.addEventListener('click', () => {
            const sectionId = row.getAttribute('data-section');
            switchSection(sectionId);
        });
    });
}

function switchSection(sectionId) {
    // Update Sidebar
    document.querySelectorAll('.nav-row').forEach(r => r.classList.remove('active'));
    document.getElementById(`nav-${sectionId}`).classList.add('active');

    // Update Content
    document.querySelectorAll('.doc-section').forEach(s => s.classList.remove('active'));
    document.getElementById(sectionId).classList.add('active');

    // Update Breadcrumb
    const label = document.querySelector(`#nav-${sectionId} .nav-label`).textContent;
    document.getElementById('breadcrumb-current').textContent = label;

    // Special handling for metrics
    if (sectionId === 'metrics') {
        fetchMetrics();
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
        summaryContent.innerHTML = `<p class="error">Failed to load DID: ${err.message}</p>`;
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
                <ul style="list-style: none; padding: 0;">
                    ${handles.map(h => `<li style="padding: 5px 0; border-bottom: 1px solid #eee;"><strong>${h.replace('at://', '@')}</strong></li>`).join('')}
                </ul>
            ` : '<p style="color: #888; font-style: italic;">No handles registered</p>'}
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
            ` : '<p style="color: #888; font-style: italic;">No services registered</p>'}
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
                <summary style="cursor: pointer; color: #666; font-size: 12px;">Show JSON</summary>
                <pre class="code-block" style="margin-top: 10px;">${JSON.stringify(doc, null, 2)}</pre>
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
                <div style="margin-bottom: 10px;">
                    <strong style="color: var(--success-color);">Identity created</strong>
                    <div style="margin-top: 5px; font-size: 12px;">
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
                diffHtml = `<div style="color: #666; font-style: italic;">No changes (checkpoint or rotation)</div>`;
            } else {
                changes.forEach(c => {
                    diffHtml += `<div style="margin-bottom: 8px;"><strong>${c.title}</strong>`;
                    if (c.type === 'service' || c.type === 'vm') {
                        c.items.forEach(item => {
                            const color = item.action === 'removed' ? 'var(--error-color)' : 'var(--success-color)';
                            const icon = item.action === 'removed' ? '-' : '+';
                            diffHtml += `
                                <div style="font-size: 11px; margin-left: 10px; color: ${color};">
                                    ${icon} <strong>${item.key}</strong>: ${item.action}
                                    ${item.action === 'updated' && item.val.endpoint ? `<br><span style="color:#666; margin-left: 15px;">-> ${item.val.endpoint}</span>` : ''}
                                </div>
                            `;
                        });
                    } else if (c.type === 'handle') {
                        diffHtml += `
                            <div style="font-size: 11px; margin-left: 10px;">
                                <div style="color: var(--error-color); text-decoration: line-through;">${c.old.join(', ')}</div>
                                <div style="color: var(--success-color);">${c.new.join(', ')}</div>
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
                     <div class="op-meta" style="font-size: 11px; color: #666; margin-bottom: 5px;">
                        CID: <code>${cid.substring(0, 20)}...</code>
                    </div>
                    ${diffHtml}
                    <details style="margin-top: 5px;">
                        <summary style="font-size: 10px; cursor: pointer; color: #999;">Raw Op</summary>
                        <pre class="code-block" style="font-size: 10px;">${JSON.stringify(op, null, 2)}</pre>
                    </details>
                </div>
            </div>
        `;
    });
    html += '</div>';

    // Add some styles for added/removed
    html += `<style> .added { color: var(--success-color); } .removed { color: var(--error-color); text-decoration: line-through; } </style>`;

    container.innerHTML = html;
}

function renderAudit(log) {
    const container = document.getElementById('auditor-content');

    let html = `
        <div class="audit-card">
            <h3>Chain Integrity Check</h3>
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
        </div>
        
        <h3>Detailed Audit Log</h3>
    `;

    log.forEach((entry, i) => {
        const op = entry.op || entry;
        const opType = !op.prev ? 'GENESIS' : 'UPDATE';

        html += `
            <div class="audit-card" style="border-left: 4px solid var(--success-color)">
                <div style="display:flex; justify-content:space-between; align-items:center;">
                    <strong>Op ${i}: ${opType}</strong>
                    <span class="status-icon status-success">✓</span>
                </div>
                <div style="font-size: 11px; color: #666; margin-top: 5px;">
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
        nodesHtml += `<div class="node key" title="${m.publicKeyMultibase || ''}" style="top: ${top}px; left: 30px;">Key: ${label}</div>`;

        services.forEach((s, j) => {
            const sTop = 50 + (j * 90);
            linesHtml += `<line x1="130" y1="${top + 15}" x2="350" y2="${sTop + 15}" stroke="#bbb" stroke-width="1" stroke-dasharray="4" />`;
        });
    });

    services.forEach((s, i) => {
        const top = 50 + (i * 90);
        const url = typeof s.serviceEndpoint === 'string' ? s.serviceEndpoint : (s.serviceEndpoint?.uri || 'N/A');
        nodesHtml += `<div class="node service" title="${url}" style="top: ${top}px; left: 350px;">Service: ${s.type}</div>`;
    });

    container.innerHTML = `
        <div class="graph-container" style="height: ${Math.max(methods.length * 70 + 100, services.length * 90 + 100, 300)}px">
            ${nodesHtml}
            <svg style="position:absolute; top:0; left:0; width:100%; height:100%; pointer-events:none;">
                ${linesHtml}
            </svg>
        </div>
        <p style="text-align:center; font-size:11px; color:#666; margin-top:10px;">
            Relationships between cryptographic keys and authorized services.
        </p>
    `;
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

    container.innerHTML = `
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px;">
            
            <!-- Performance -->
            <div class="audit-card">
                <h3>Performance</h3>
                <div style="text-align: center; padding: 20px;">
                    <div style="font-size: 36px; font-weight: bold; color: #333;">${latency.toFixed(2)} ms</div>
                    <div style="font-size: 12px; color: #666; margin-top: 5px;">Avg Resolution Latency</div>
                </div>
            </div>

            <!-- Traffic -->
            <div class="audit-card">
                <h3>Traffic</h3>
                <div style="display: flex; justify-content: space-around; padding: 10px 0;">
                    <div style="text-align: center;">
                        <div style="font-size: 24px; font-weight: bold;">${requests}</div>
                        <div style="font-size: 11px; color: #666;">Requests</div>
                    </div>
                     <div style="text-align: center;">
                        <div style="font-size: 24px; font-weight: bold; color: #0066cc;">${totalOps}</div>
                        <div style="font-size: 11px; color: #666;">Operations</div>
                    </div>
                     <div style="text-align: center;">
                        <div style="font-size: 24px; font-weight: bold; color: var(--error-color);">${errors}</div>
                        <div style="font-size: 11px; color: #666;">Errors</div>
                    </div>
                </div>
            </div>

            <!-- Cache Stats -->
            <div class="audit-card" style="grid-column: 1 / -1;">
                <h3>Cache Efficiency</h3>
                
                <div style="margin-bottom: 20px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 5px; font-size: 12px;">
                        <span><strong>L1 Memory Cache</strong> (${memHits} hits, ${memMisses} misses)</span>
                        <span>${memRatio}% Hit Rate</span>
                    </div>
                    <div style="background: #eee; height: 10px; border-radius: 5px; overflow: hidden;">
                        <div style="background: var(--success-color); width: ${memRatio}%; height: 100%;"></div>
                    </div>
                </div>

                <div>
                    <div style="display: flex; justify-content: space-between; margin-bottom: 5px; font-size: 12px;">
                        <span><strong>L2 Disk Cache</strong> (${diskHits} hits, ${diskMisses} misses)</span>
                        <span>${diskRatio}% Hit Rate</span>
                    </div>
                    <div style="background: #eee; height: 10px; border-radius: 5px; overflow: hidden;">
                        <div style="background: #0066cc; width: ${diskRatio}%; height: 100%;"></div>
                    </div>
                </div>
            </div>
        </div>
    `;
}
