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
        <p class="description">
            The DID Document is a JSON-LD object that serves as the root of the identity. 
            It contains the public keys for verification and the service endpoints for interacting with the identity.
        </p>

        <div class="summary-table">
            <h3>Identity Properties</h3>
            <table>
                <tr>
                    <th style="width: 150px">Property</th>
                    <th>Value</th>
                </tr>
                <tr>
                    <td><strong>id</strong></td>
                    <td><code>${escapeHtml(doc.id)}</code></td>
                </tr>
    `;

    if (doc.alsoKnownAs && doc.alsoKnownAs.length > 0) {
        html += `
            <tr>
                <td><strong>alsoKnownAs</strong></td>
                <td><a href="#">${escapeHtml(doc.alsoKnownAs[0])}</a></td>
            </tr>
        `;
    }
    html += '</table></div>';

    if (keys.length > 0) {
        html += `
            <h3>Verification Methods</h3>
            <p class="description">Cryptographic keys used to verify signatures and authenticate updates.</p>
            <table>
                <tr>
                    <th>ID</th>
                    <th>Type</th>
                    <th>Public Key</th>
                </tr>
        `;
        for (const key of keys) {
            const shortKey = key.key ? key.key.slice(0, 16) + '...' : 'N/A';
            const shortId = key.id.startsWith(doc.id) ? key.id.slice(doc.id.length) : key.id;
            html += `
                <tr>
                    <td><code>${escapeHtml(shortId)}</code></td>
                    <td>${escapeHtml(key.type)}</td>
                    <td><code>${escapeHtml(shortKey)}</code></td>
                </tr>
            `;
        }
        html += '</table>';
    }

    if (services.length > 0) {
        html += `
            <h3>Services</h3>
            <p class="description">Endpoint identifiers for interacting with the identity agent.</p>
            <table>
                <tr>
                    <th>ID</th>
                    <th>Type</th>
                    <th>Endpoint</th>
                </tr>
        `;
        for (const svc of services) {
            const shortId = svc.id.startsWith(doc.id) ? svc.id.slice(doc.id.length) : svc.id;
            html += `
                <tr>
                    <td><code>${escapeHtml(shortId)}</code></td>
                    <td>${escapeHtml(svc.type)}</td>
                    <td><a href="${escapeHtml(svc.endpoint)}" target="_blank">${escapeHtml(svc.endpoint)}</a></td>
                </tr>
            `;
        }
        html += '</table>';
    }

    html += `
        <h3>Full DID Document</h3>
        <pre class="code-block">${escapeHtml(JSON.stringify(doc, null, 2))}</pre>
        
        <h3 class="see-also">See Also</h3>
        <ul class="see-also-links">
            <li><a href="#" onclick="window.openWindow('plc-ops'); return false;">PLC Operations</a></li>
            <li><a href="#" onclick="window.openWindow('collections'); return false;">Collections</a></li>
            <li><a href="https://atproto.com/specs/did" target="_blank">ATProto DID Specification</a></li>
        </ul>
    `;

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
