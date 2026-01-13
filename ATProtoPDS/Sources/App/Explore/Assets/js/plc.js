export async function fetchPlcLog(did) {
    const response = await fetch(`/api/plc-log?did=${encodeURIComponent(did)}`);
    if (!response.ok) {
        return { error: `HTTP ${response.status}` };
    }
    return await response.json();
}

export function renderPlcOperations(operations) {
    if (!operations || operations.length === 0) {
        return '<p class="empty">No PLC operations found for this DID</p>';
    }

    if (operations.error) {
        return `<p class="error">${escapeHtml(operations.error)}</p>`;
    }

    let html = `
        <p class="description">
            The following table lists the PLC (Public Ledger of Credentials) operations recorded for this identity. 
            Each operation represents a modification to the identity state.
        </p>
        
        <table class="param-table">
            <tr>
                <th style="width: 50px">#</th>
                <th style="width: 140px">Type</th>
                <th>CID</th>
                <th>Timestamp</th>
            </tr>
    `;

    for (let i = 0; i < operations.length; i++) {
        const entry = operations[i];
        // Handle both audit format (operation wrapper) and direct format
        const op = entry.operation || entry;
        const opType = op.type || 'unknown';
        const cid = entry.cid || 'N/A';
        const timestamp = entry.createdAt ? formatTimestamp(entry.createdAt) : 'N/A';

        html += `
            <tr>
                <td>${i}</td>
                <td><strong>${escapeHtml(formatOpType(opType))}</strong></td>
                <td><code title="${escapeHtml(cid)}">${escapeHtml(typeof cid === 'string' && cid.length > 16 ? cid.slice(0, 16) + '...' : cid)}</code></td>
                <td>${escapeHtml(timestamp)}</td>
            </tr>
        `;
    }

    html += '</table>';

    // Add details section
    html += '<h3>Operation Details</h3>';

    for (let i = 0; i < operations.length; i++) {
        const entry = operations[i];
        const op = entry.operation || entry;
        const opType = op.type || 'unknown';

        html += `
            <div class="op-detail" style="margin-bottom: 20px;">
                <h4>Operation ${i}: ${escapeHtml(formatOpType(opType))}</h4>
        `;

        // Show operation metadata
        if (entry.cid || entry.createdAt) {
            html += `<div class="op-meta" style="margin-bottom: 10px; font-size: 11px; color: #666;">`;
            if (entry.cid) html += `CID: <code>${escapeHtml(entry.cid)}</code> `;
            if (entry.createdAt) html += `• Time: ${escapeHtml(formatTimestamp(entry.createdAt))}`;
            if (entry.nullified) html += ` • <span style="color: #c00;">NULLIFIED</span>`;
            html += `</div>`;
        }

        // Show operation content in a structured way
        html += renderOperationContent(op);

        html += `</div>`;
    }

    html += `
        <h3 class="see-also">See Also</h3>
        <ul class="see-also-links">
            <li><a href="#" onclick="document.getElementById('nav-did-doc').click(); return false;">DID Document</a></li>
            <li><a href="https://github.com/did-method-plc/did-method-plc" target="_blank">PLC Specification</a></li>
            <li><a href="https://plc.directory" target="_blank">PLC Directory</a></li>
        </ul>
    `;

    return html;
}

function renderOperationContent(op) {
    let html = '<div class="op-content" style="background: #f9f9f9; border: 1px solid #ddd; border-radius: 4px; padding: 12px;">';

    // Services
    if (op.services && Object.keys(op.services).length > 0) {
        html += '<div class="op-section" style="margin-bottom: 12px;"><strong>Services:</strong>';
        html += '<table style="margin-top: 5px; font-size: 12px;"><tr><th>ID</th><th>Type</th><th>Endpoint</th></tr>';
        for (const [id, svc] of Object.entries(op.services)) {
            html += `<tr><td>${escapeHtml(id)}</td><td>${escapeHtml(svc.type || '')}</td><td><a href="${escapeHtml(svc.endpoint || '')}" target="_blank">${escapeHtml(svc.endpoint || '')}</a></td></tr>`;
        }
        html += '</table></div>';
    }

    // Also Known As (handles)
    if (op.alsoKnownAs && op.alsoKnownAs.length > 0) {
        html += '<div class="op-section" style="margin-bottom: 12px;"><strong>Handles:</strong><ul style="margin: 5px 0 0 20px;">';
        for (const aka of op.alsoKnownAs) {
            html += `<li><code>${escapeHtml(aka)}</code></li>`;
        }
        html += '</ul></div>';
    }

    // Verification Methods
    if (op.verificationMethods && Object.keys(op.verificationMethods).length > 0) {
        html += '<div class="op-section" style="margin-bottom: 12px;"><strong>Verification Methods:</strong>';
        html += '<table style="margin-top: 5px; font-size: 12px;"><tr><th>ID</th><th>Key</th></tr>';
        for (const [id, key] of Object.entries(op.verificationMethods)) {
            const shortKey = typeof key === 'string' && key.length > 40 ? key.slice(0, 40) + '...' : key;
            html += `<tr><td>${escapeHtml(id)}</td><td><code title="${escapeHtml(key)}">${escapeHtml(shortKey)}</code></td></tr>`;
        }
        html += '</table></div>';
    }

    // Rotation Keys
    if (op.rotationKeys && op.rotationKeys.length > 0) {
        html += '<div class="op-section" style="margin-bottom: 12px;"><strong>Rotation Keys:</strong><ul style="margin: 5px 0 0 20px; font-size: 12px;">';
        for (const key of op.rotationKeys) {
            const shortKey = typeof key === 'string' && key.length > 50 ? key.slice(0, 50) + '...' : key;
            html += `<li><code title="${escapeHtml(key)}">${escapeHtml(shortKey)}</code></li>`;
        }
        html += '</ul></div>';
    }

    // Previous operation
    if (op.prev) {
        html += `<div class="op-section" style="margin-bottom: 12px;"><strong>Previous:</strong> <code>${escapeHtml(op.prev)}</code></div>`;
    } else if (op.prev === null) {
        html += `<div class="op-section" style="margin-bottom: 12px;"><strong>Previous:</strong> <em>none (genesis operation)</em></div>`;
    }

    // Signature
    if (op.sig) {
        const shortSig = op.sig.length > 20 ? op.sig.slice(0, 20) + '...' : op.sig;
        html += `<div class="op-section"><strong>Signature:</strong> <code title="${escapeHtml(op.sig)}">${escapeHtml(shortSig)}</code></div>`;
    }

    html += '</div>';
    return html;
}

function formatOpType(type) {
    const typeMap = {
        'plc_operation': 'PLC Operation',
        'create': 'Create',
        'plc_tombstone': 'Tombstone',
        'unknown': 'Unknown'
    };
    return typeMap[type] || type;
}

function formatTimestamp(isoString) {
    if (!isoString) return '';
    try {
        const date = new Date(isoString);
        return date.toLocaleString();
    } catch {
        return isoString;
    }
}

function escapeHtml(str) {
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
