// Derive PLC base URL from current page origin
const PLC_BASE = (function() {
    const loc = window.location;
    const host = loc.hostname;
    if (host.endsWith('garazyk.xyz')) {
        return loc.protocol + '//plc.garazyk.xyz';
    }
    // For exe.dev proxy or other hosts, PLC is on port 4000
    return loc.protocol + '//' + host + ':4000';
})();

export async function fetchPlcLog(did) {
    const response = await fetch(`/api/pds/plc-log?did=${encodeURIComponent(did)}`);
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
            The Public Ledger of Credentials (PLC) records the identity history. 
            Below is the sequence of operations that define the current state of this DID.
        </p>
        
        <div class="timeline-container">
    `;

    for (let i = 0; i < operations.length; i++) {
        const entry = operations[i];
        const op = entry.op || entry;
        const opType = op.type || 'unknown';
        const cid = entry.cid || 'N/A';
        const timestamp = entry.createdAt || 'N/A';
        const isGenesis = i === 0;

        html += `
            <div class="timeline-entry">
                <div class="timeline-dot ${isGenesis ? 'timeline-dot-genesis' : 'timeline-dot-update'}"></div>
                <div class="op-card">
                    <div class="op-card-header">
                        <span class="op-card-type">${escapeHtml(opType.toUpperCase())}</span>
                        <span class="op-card-time">${escapeHtml(timestamp)}</span>
                    </div>
                    <div class="op-card-meta">
                        CID: <code>${escapeHtml(typeof cid === 'string' ? cid.slice(0, 12) + '...' : JSON.stringify(cid))}</code>
                    </div>
                    <pre class="code-block op-card-json">${escapeHtml(JSON.stringify(op, null, 2))}</pre>
                </div>
            </div>
        `;
    }

    html += '</div>';

    html += `
        <h3 class="see-also">Tools</h3>
        <ul class="see-also-links">
            <li><a href="${PLC_BASE}" target="_blank">Open Campagnola</a></li>
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
