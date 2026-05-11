// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * SkyLab Admin Panel — Service health, account search, AppView monitoring.
 */

function initAdminPanel(bridge) {
    const servicesEl = document.getElementById('admin-services');

    const HEALTH_ENDPOINTS = {
        pds: '/xrpc/com.atproto.server.describeServer',
        appview: '/admin/backfill/status',
        relay: '/api/relay/health',
        plc: '/_health',
        chat: '/_health',
        video: '/_health',
        germ: '/_health',
    };

    let refreshTimer = null;

    // ---- Service health ----
    async function checkServiceHealth() {
        const services = bridge.services || {};
        const cards = [];

        for (const [name, baseUrl] of Object.entries(services)) {
            const healthPath = HEALTH_ENDPOINTS[name] || '/_health';
            const proxyUrl = bridge.useProxy
                ? `${bridge.proxyBase}/${name}${healthPath}`
                : `${baseUrl}${healthPath}`;

            let status = 'unknown';
            let detail = '';
            try {
                const resp = await fetch(proxyUrl, { signal: AbortSignal.timeout(5000) });
                status = resp.ok ? 'healthy' : 'unhealthy';
                if (resp.ok) {
                    try { detail = await resp.text(); } catch(e) {}
                } else {
                    detail = `HTTP ${resp.status}`;
                }
            } catch (e) {
                status = 'unhealthy';
                detail = e.name === 'TimeoutError' ? 'timeout' : 'connection refused';
            }

            cards.push({ name, baseUrl, status, detail });
        }

        renderServiceCards(cards);
    }

    function renderServiceCards(cards) {
        servicesEl.innerHTML = '';

        // Service cards
        const grid = document.createElement('div');
        grid.style.cssText = 'display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:var(--space-md);margin-bottom:var(--space-xl);';

        for (const card of cards) {
            const el = document.createElement('div');
            el.className = 'skylab-service-card';
            el.innerHTML = `
                <div class="skylab-service-status ${card.status}"></div>
                <div>
                    <div class="skylab-service-name">${escapeHtml(card.name)}</div>
                    <div class="skylab-service-url">${escapeHtml(card.baseUrl)}</div>
                    ${card.detail ? `<div style="font-size:var(--font-size-xs);color:var(--color-text-tertiary);margin-top:2px;">${escapeHtml(card.detail.substring(0, 80))}</div>` : ''}
                </div>
            `;
            grid.appendChild(el);
        }
        servicesEl.appendChild(grid);

        // Account search
        const searchSection = document.createElement('div');
        searchSection.className = 'skylab-card';
        searchSection.style.marginBottom = 'var(--space-xl)';
        searchSection.innerHTML = `
            <h3 class="skylab-card-title">Account Search</h3>
            <div style="display:flex;gap:var(--space-sm);margin-bottom:var(--space-md);">
                <input type="text" class="skylab-form-input" id="admin-search-input"
                       placeholder="Email or DID" style="flex:1;">
                <button class="skylab-btn skylab-btn-primary skylab-btn-sm" id="admin-search-btn">Search</button>
            </div>
            <div id="admin-search-results"></div>
        `;
        servicesEl.appendChild(searchSection);

        // AppView monitoring
        const appviewSection = document.createElement('div');
        appviewSection.className = 'skylab-card';
        appviewSection.innerHTML = `
            <h3 class="skylab-card-title">AppView Monitoring</h3>
            <div id="admin-appview-status">Loading...</div>
        `;
        servicesEl.appendChild(appviewSection);

        // Wire up search
        document.getElementById('admin-search-btn')?.addEventListener('click', doAccountSearch);
        document.getElementById('admin-search-input')?.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') doAccountSearch();
        });

        // Load AppView status
        loadAppViewStatus();
    }

    async function doAccountSearch() {
        const input = document.getElementById('admin-search-input');
        const resultsEl = document.getElementById('admin-search-results');
        if (!input || !resultsEl) return;

        const query = input.value.trim();
        if (!query) return;

        resultsEl.innerHTML = '<div class="skylab-empty-state">Searching...</div>';

        const resp = await bridge.xrpc('com.atproto.admin.getAccountInfos', { id: query }, null, {
            service: 'pds', auth: true,
        });

        if (resp.ok && resp.data) {
            const infos = resp.data.infos || [resp.data];
            if (infos.length === 0) {
                resultsEl.innerHTML = '<div class="skylab-empty-state">No results</div>';
                return;
            }
            let html = '<table class="skylab-admin-table" style="width:100%;font-size:var(--font-size-xs);border-collapse:collapse;">';
            html += '<thead><tr><th>Handle</th><th>DID</th><th>Email</th><th>Status</th></tr></thead><tbody>';
            for (const info of infos) {
                html += `<tr>
                    <td style="padding:var(--space-xs);">${escapeHtml(info.handle || '—')}</td>
                    <td style="padding:var(--space-xs);font-family:var(--font-mono);">${escapeHtml(info.did || '—')}</td>
                    <td style="padding:var(--space-xs);">${escapeHtml(info.email || '—')}</td>
                    <td style="padding:var(--space-xs);">${escapeHtml(info.status || '—')}</td>
                </tr>`;
            }
            html += '</tbody></table>';
            resultsEl.innerHTML = html;
        } else {
            resultsEl.innerHTML = `<div class="skylab-empty-state">Search failed: ${escapeHtml(resp.data?.error || 'unknown')}</div>`;
        }
    }

    async function loadAppViewStatus() {
        const el = document.getElementById('admin-appview-status');
        if (!el) return;

        const resp = await bridge.xrpc('admin.backfill.getStatus', null, null, {
            service: 'appview', auth: true,
        });

        if (resp.ok && resp.data) {
            el.innerHTML = `<pre style="font-size:var(--font-size-xs);color:var(--color-text-secondary);overflow:auto;max-height:200px;">${escapeHtml(JSON.stringify(resp.data, null, 2))}</pre>`;
        } else {
            el.innerHTML = '<div class="skylab-empty-state">AppView status unavailable</div>';
        }
    }

    // ---- Auto-refresh ----
    function startAutoRefresh() {
        if (refreshTimer) clearInterval(refreshTimer);
        refreshTimer = setInterval(checkServiceHealth, 30000);
    }

    // ---- Init ----
    checkServiceHealth();
    startAutoRefresh();

    // ---- HTML escaping ----
    function escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str || '';
        return div.innerHTML;
    }
}
