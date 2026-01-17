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
        
        <div class="timeline-container" style="position: relative; padding: 10px 0;">
    `;

    for (let i = 0; i < operations.length; i++) {
        const entry = operations[i];
        const op = entry.op || entry;
        const opType = op.type || 'unknown';
        const cid = entry.cid || 'N/A';
        const timestamp = entry.createdAt || 'N/A';
        const isGenesis = i === 0;

        html += `
            <div class="timeline-item" style="position: relative; padding-left: 30px; margin-bottom: 20px; border-left: 2px solid #ccc;">
                <div class="timeline-marker" style="position: absolute; left: -7px; top: 0; width: 12px; height: 12px; border-radius: 50%; background: ${isGenesis ? '#28a745' : '#0066cc'}; border: 2px solid white;"></div>
                <div class="op-card" style="background: #f9f9f9; border: 1px solid #ddd; border-radius: 4px; padding: 10px;">
                    <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 5px;">
                        <span style="font-weight: bold; color: #333;">${escapeHtml(opType.toUpperCase())}</span>
                        <span style="font-size: 11px; color: #999;">${escapeHtml(timestamp)}</span>
                    </div>
                    <div style="font-size: 11px; color: #666; margin-bottom: 8px;">
                        CID: <code>${escapeHtml(typeof cid === 'string' ? cid.slice(0, 12) + '...' : JSON.stringify(cid))}</code>
                    </div>
                    <pre style="font-family: monospace; font-size: 11px; background: #eee; padding: 8px; border-radius: 3px; margin: 0; overflow-x: auto;">${escapeHtml(JSON.stringify(op, null, 2))}</pre>
                </div>
            </div>
        `;
    }

    html += '</div>';

    html += `
        <h3 class="see-also">Tools</h3>
        <ul class="see-also-links">
            <li><a href="http://localhost:2582" target="_blank">Open Standalone PLC Explorer</a></li>
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
