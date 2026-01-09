export function renderDidDocument(doc) {
    if (!doc) {
        return '<p class="error">DID document not found</p>';
    }
    
    return `<pre class="code-block">${escapeHtml(JSON.stringify(doc, null, 2))}</pre>`;
}

export function extractKeyInfo(doc) {
    if (!doc || !doc.verificationMethod) {
        return [];
    }
    
    return doc.verificationMethod.map(vm => ({
        id: vm.id,
        type: vm.type,
        controller: vm.controller,
        key: vm.publicKeyMultibase
    }));
}

export function extractServices(doc) {
    if (!doc || !doc.service) {
        return [];
    }
    
    return doc.service.map(s => ({
        id: s.id,
        type: s.type,
        endpoint: typeof s.serviceEndpoint === 'string' 
            ? s.serviceEndpoint 
            : JSON.stringify(s.serviceEndpoint)
    }));
}

export function renderDidSummary(doc) {
    if (!doc) {
        return '<p class="error">DID document not found</p>';
    }
    
    const keys = extractKeyInfo(doc);
    const services = extractServices(doc);
    
    let html = `
        <div class="did-summary">
            <div class="did-header">
                <span class="did-label">DID</span>
                <code class="did-value">${escapeHtml(doc.id)}</code>
            </div>
    `;
    
    if (doc.alsoKnownAs && doc.alsoKnownAs.length > 0) {
        html += `
            <div class="did-also-known-as">
                <span class="did-label">Also Known As</span>
                <code class="did-value">${escapeHtml(doc.alsoKnownAs[0])}</code>
            </div>
        `;
    }
    
    if (keys.length > 0) {
        html += `
            <div class="did-section">
                <h3>Verification Methods (${keys.length})</h3>
                <ul class="key-list">
        `;
        for (const key of keys.slice(0, 5)) {
            html += `
                <li class="key-item">
                    <span class="key-id">${escapeHtml(key.id)}</span>
                    <span class="key-type">${escapeHtml(key.type)}</span>
                    <code class="key-fingerprint">${escapeHtml(key.key ? key.key.slice(0, 12) + '...' : 'N/A')}</code>
                </li>
            `;
        }
        if (keys.length > 5) {
            html += `<li class="key-item more">+${keys.length - 5} more...</li>`;
        }
        html += '</ul></div>';
    }
    
    if (services.length > 0) {
        html += `
            <div class="did-section">
                <h3>Services (${services.length})</h3>
                <ul class="service-list">
        `;
        for (const svc of services) {
            html += `
                <li class="service-item">
                    <span class="service-id">${escapeHtml(svc.id)}</span>
                    <span class="service-type">${escapeHtml(svc.type)}</span>
                    <span class="service-endpoint">${escapeHtml(svc.endpoint)}</span>
                </li>
            `;
        }
        html += '</ul></div>';
    }
    
    html += '</div>';
    return html;
}

function escapeHtml(str) {
    if (!str) return '';
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
