export async function fetchPlcLog(did) {
    const response = await fetch(`/explore/api/plc-log?did=${encodeURIComponent(did)}`);
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
    
    let html = '<div class="plc-operations">';
    
    for (let i = 0; i < operations.length; i++) {
        const op = operations[i];
        const opData = op.op || {};
        const opType = opData.type || 'unknown';
        
        html += `
            <div class="plc-operation">
                <div class="op-header">
                    <span class="op-number">Operation ${i}</span>
                    <span class="op-type">${escapeHtml(opType)}</span>
                </div>
                <pre class="op-json">${escapeHtml(JSON.stringify(opData, null, 2))}</pre>
                <div class="op-meta">
        `;
        
        if (op.prev) {
            html += `<span class="op-prev">prev: ${escapeHtml(op.prev.slice(0, 12))}...</span>`;
        }
        if (op.sig) {
            html += `<span class="op-sig">sig: ${escapeHtml(op.sig.slice(0, 12))}...</span>`;
        }
        if (op.rotationKeys) {
            html += `<span class="op-keys">${op.rotationKeys.length} rotation keys</span>`;
        }
        
        html += `
                </div>
            </div>
        `;
    }
    
    html += '</div>';
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
