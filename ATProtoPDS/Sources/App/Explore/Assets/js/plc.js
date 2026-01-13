export async function fetchPlcLog(did) {
    const response = await fetch(`/api/plc-log?did=${encodeURIComponent(did)}`);
    if (!response.ok) {
        return { error: `HTTP ${response.status}` };
    }
    return await response.json();
}

export function renderPlcOperations(operations) {
    if (!operations || operations.length === 0) {
        return '<p class="empty">No operations found for this DID</p>';
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
                <th style="width: 120px">Type</th>
                <th>CID</th>
                <th>Timestamp</th>
            </tr>
    `;

    for (let i = 0; i < operations.length; i++) {
        const op = operations[i];
        const opData = op.op || {};
        const opType = opData.type || 'unknown';
        const cid = op.cid || 'N/A';
        const timestamp = op.createdAt || 'N/A';

        html += `
            <tr>
                <td>${i}</td>
                <td><strong>${escapeHtml(opType)}</strong></td>
                <td><code>${escapeHtml(typeof cid === 'string' ? cid.slice(0, 12) + '...' : JSON.stringify(cid))}</code></td>
                <td>${escapeHtml(timestamp)}</td>
            </tr>
        `;
    }

    html += '</table>';

    // Add details section
    html += '<h3>Operation Details</h3>';

    for (let i = 0; i < operations.length; i++) {
        const op = operations[i];
        const opData = op.op || {};

        html += `
            <div class="op-detail">
                <h4>Operation ${i}: ${escapeHtml(opData.type || 'unknown')}</h4>
                <div class="op-meta" style="margin-bottom: 10px; font-size: 11px; color: #666;">
                    ${op.cid ? 'CID: ' + escapeHtml(op.cid) + ' • ' : ''}
                    ${op.createdAt ? 'Time: ' + escapeHtml(op.createdAt) : ''}
                </div>
                <pre class="code-block">${escapeHtml(JSON.stringify(opData, null, 2))}</pre>
            </div>
        `;
    }

    html += `
        <h3 class="see-also">See Also</h3>
        <ul class="see-also-links">
            <li><a href="#" onclick="document.getElementById('nav-did-doc').click(); return false;">DID Document</a></li>
            <li><a href="https://github.com/did-method-plc/did-method-plc" target="_blank">PLC Specification</a></li>
        </ul>
    `;

    return html;
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
