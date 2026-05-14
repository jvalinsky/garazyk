(function(global) {
    'use strict';

    function initSearchPanel(bridge) {
        const container = document.getElementById('panel-search');
        if (!container) return;

        container.innerHTML =
            '<div class="skylab-panel-header">' +
                '<h1 class="skylab-panel-title">Search</h1>' +
            '</div>' +
            '<div class="skylab-search-bar">' +
                '<input type="text" class="skylab-form-input" id="search-input" placeholder="Search actors or posts\u2026">' +
                '<button class="skylab-btn skylab-btn-primary skylab-btn-sm" id="search-submit">Search</button>' +
            '</div>' +
            '<div class="skylab-tab-bar" id="search-tabs" style="display:none">' +
                '<button class="skylab-tab active" data-tab="actors">Actors</button>' +
                '<button class="skylab-tab" data-tab="posts">Posts</button>' +
            '</div>' +
            '<div class="skylab-search-results" id="search-results">' +
                '<div class="skylab-empty-state">Enter a query to search</div>' +
            '</div>';

        const input = document.getElementById('search-input');
        const submit = document.getElementById('search-submit');
        const results = document.getElementById('search-results');
        const tabs = document.getElementById('search-tabs');

        let currentQuery = '';
        let actorsCache = [];
        let postsCache = [];

        function showResults(msg) {
            results.innerHTML = '<div class="skylab-empty-state">' + msg + '</div>';
        }

        function showActors() {
            if (actorsCache.length === 0) { showResults('No actors found'); return; }
            results.innerHTML = '';
            for (const actor of actorsCache) {
                const card = document.createElement('a');
                card.className = 'skylab-person-card';
                card.href = '#/profile/' + (actor.handle || actor.did);
                card.innerHTML = '<div class="skylab-person-avatar">' +
                    ((actor.displayName || actor.handle || '?').slice(0, 2).toUpperCase()) +
                    '</div><div class="skylab-person-info"><div class="skylab-person-name">' +
                    (actor.displayName || actor.handle || 'Unknown') +
                    '</div><div class="skylab-person-handle">@' + (actor.handle || '') + '</div></div>';
                if (actor.description) {
                    const desc = document.createElement('div');
                    desc.className = 'skylab-person-description';
                    desc.textContent = actor.description.slice(0, 100);
                    card.appendChild(desc);
                }
                results.appendChild(card);
            }
        }

        function showPosts() {
            if (postsCache.length === 0) { showResults('No posts found'); return; }
            results.innerHTML = '';
            for (const item of postsCache) {
                const el = SkyLabPost.renderPost(item, { noThreadLink: false });
                if (el) {
                    el.addEventListener('skylab-navigate', (e) => {
                        const { route, params } = e.detail;
                        window.location.hash = '#/' + route + '/' + params.join('/');
                    });
                    results.appendChild(el);
                }
            }
        }

        function setActiveTab(tabId) {
            tabs.querySelectorAll('.skylab-tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tabId));
            if (tabId === 'actors') showActors();
            else showPosts();
        }

        async function doSearch() {
            const q = input.value.trim();
            if (!q) return;
            currentQuery = q;
            tabs.style.display = 'none';
            showResults('Searching\u2026');

            const [actorsResp, postsResp] = await Promise.all([
                bridge.xrpc('app.bsky.actor.searchActors', { q, limit: 20 }, null, { service: 'appview', auth: !!bridge.auth }),
                bridge.xrpc('app.bsky.feed.searchPosts', { q, limit: 20 }, null, { service: 'appview', auth: !!bridge.auth }),
            ]);

            actorsCache = Array.isArray(actorsResp.data?.actors) ? actorsResp.data.actors : [];
            postsCache = Array.isArray(postsResp.data?.posts) ? postsResp.data.posts : [];

            tabs.style.display = 'flex';
            setActiveTab('actors');
        }

        tabs.addEventListener('click', (e) => {
            const tab = e.target.closest('.skylab-tab');
            if (tab) setActiveTab(tab.dataset.tab);
        });

        submit.addEventListener('click', doSearch);
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSearch(); });

        results.addEventListener('click', (e) => {
            const card = e.target.closest('.skylab-person-card');
            if (card && card.getAttribute('href')) {
                e.preventDefault();
                window.location.hash = card.getAttribute('href');
            }
        });
    }

    global.initSearchPanel = initSearchPanel;
    if (typeof module !== 'undefined' && module.exports) module.exports = { initSearchPanel };
})(typeof window !== 'undefined' ? window : globalThis);
