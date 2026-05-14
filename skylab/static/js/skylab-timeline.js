// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

/**
 * Timeline panel for SkyLab.
 *
 * This module wires the composer, timeline loading, and firehose-driven
 * updates into the shared SkyLabBridge event bus.
 */

(function initTimelineModule(global) {
    'use strict';

    const COMPOSER_MAX_LENGTH = 300;

    /**
     * Initialize the timeline panel UI.
     *
     * @param {SkyLabBridge} bridge - Shared application bridge.
     */
    function initTimelinePanel(bridge) {
        if (!bridge) {
            throw new Error('initTimelinePanel requires a bridge instance');
        }

        // Avoid attaching duplicate listeners if the panel is initialized twice.
        if (bridge._timelinePanelInitialized) {
            return;
        }

        const composerTextEl = document.getElementById('composer-text');
        const composerCountEl = document.getElementById('composer-char-count');
        const composerPostEl = document.getElementById('composer-post');
        const refreshEl = document.getElementById('timeline-refresh');
        const feedEl = document.getElementById('timeline-feed');
        const composerEl = document.getElementById('timeline-composer');

        if (!feedEl) {
            console.warn('SkyLab timeline panel could not initialize: #timeline-feed not found');
            return;
        }

        bridge._timelinePanelInitialized = true;

        const seenUris = new Set();
        let composerErrorEl = null;
        let loading = false;
        let timelineLoadVersion = 0;

        // --------------------------------------------------------------------
        // Small DOM helpers
        // --------------------------------------------------------------------

        function getCanonicalPost(item) {
            if (!item) {
                return null;
            }

            // Timeline responses typically wrap the post in `item.post`.
            if (item.post && (item.post.uri || item.post.cid || item.post.record)) {
                return item.post;
            }

            return item;
        }

        function getPostUri(post) {
            return post?.uri || '';
        }

        function getAuthor(post) {
            return post?.author || null;
        }

        function getDisplayName(author) {
            return author?.displayName || author?.handle || 'Unknown author';
        }

        function getHandle(author) {
            if (!author) {
                return '';
            }

            return author.handle ? `@${author.handle}` : '';
        }

        function getPostText(post) {
            if (!post) {
                return '';
            }

            if (typeof post.text === 'string') {
                return post.text;
            }

            if (typeof post.record?.text === 'string') {
                return post.record.text;
            }

            return '';
        }

        function getPostTime(post) {
            return post?.record?.createdAt || post?.createdAt || post?.indexedAt || '';
        }

        function formatTimestamp(timestamp) {
            if (!timestamp) {
                return '';
            }

            const date = new Date(timestamp);
            if (Number.isNaN(date.getTime())) {
                return timestamp;
            }

            return date.toLocaleString(undefined, {
                dateStyle: 'medium',
                timeStyle: 'short',
            });
        }

        function getInitials(author) {
            const source = (author?.displayName || author?.handle || '??').trim();
            if (!source) {
                return '??';
            }

            const words = source
                .replace(/[^\p{L}\p{N}]+/gu, ' ')
                .trim()
                .split(/\s+/)
                .filter(Boolean);

            if (words.length >= 2) {
                return `${words[0][0]}${words[1][0]}`.toUpperCase();
            }

            if (words.length === 1) {
                return words[0].slice(0, 2).toUpperCase();
            }

            return source.slice(0, 2).toUpperCase();
        }

        function extractErrorMessage(data, fallbackMessage) {
            if (!data) {
                return fallbackMessage;
            }

            if (typeof data === 'string') {
                return data;
            }

            if (data.message) {
                return data.message;
            }

            if (data.detail) {
                return data.detail;
            }

            if (data.error) {
                return data.error;
            }

            return fallbackMessage;
        }

        function clearFeed() {
            feedEl.replaceChildren();
            seenUris.clear();
        }

        function showFeedMessage(message) {
            const el = document.createElement('div');
            el.className = 'skylab-empty-state';
            el.textContent = message;
            feedEl.replaceChildren(el);
        }

        function ensureComposerErrorEl() {
            if (!composerEl) {
                return null;
            }

            if (!composerErrorEl) {
                composerErrorEl = document.createElement('div');
                composerErrorEl.className = 'skylab-form-error skylab-composer-error';
                composerErrorEl.style.display = 'none';
                composerEl.appendChild(composerErrorEl);
            }

            return composerErrorEl;
        }

        function showComposerError(message) {
            const el = ensureComposerErrorEl();
            if (!el) {
                console.error(message);
                return;
            }

            el.textContent = message;
            el.style.display = 'block';
        }

        function clearComposerError() {
            if (!composerErrorEl) {
                return;
            }

            composerErrorEl.textContent = '';
            composerErrorEl.style.display = 'none';
        }

        function updateComposerCount() {
            if (!composerTextEl || !composerCountEl) {
                return;
            }

            composerCountEl.textContent = `${composerTextEl.value.length}/${COMPOSER_MAX_LENGTH}`;
        }

        function focusReplyComposer(post) {
            if (!composerTextEl) {
                return;
            }

            const author = getAuthor(post);
            const handle = author?.handle ? `@${author.handle} ` : '';
            const currentValue = composerTextEl.value.trim();

            composerTextEl.value = currentValue
                ? `${handle}${currentValue}`
                : handle;
            composerTextEl.focus();
            updateComposerCount();
            clearComposerError();
        }

        function makeActionButton(label, className) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = `skylab-btn skylab-btn-sm ${className || ''}`.trim();
            button.textContent = label;
            return button;
        }

        // --------------------------------------------------------------------
        // Post rendering
        // --------------------------------------------------------------------

        async function likePost(post, button) {
            if (!bridge.auth?.did) {
                showComposerError('Sign in to like posts.');
                return;
            }

            if (!post?.uri || !post?.cid) {
                showComposerError('This post cannot be liked because it is missing metadata.');
                return;
            }

            const originalLabel = button.textContent;
            button.disabled = true;
            button.textContent = 'Liking…';

            try {
                const resp = await bridge.xrpc(
                    'com.atproto.repo.createRecord',
                    null,
                    {
                        repo: bridge.auth.did,
                        collection: 'app.bsky.feed.like',
                        rkey: Date.now().toString(),
                        record: {
                            $type: 'app.bsky.feed.like',
                            subject: { uri: post.uri, cid: post.cid },
                            createdAt: new Date().toISOString(),
                        },
                    },
                    { service: 'pds', auth: true },
                );

                if (!resp.ok) {
                    throw new Error(extractErrorMessage(resp.data, 'Unable to like this post'));
                }

                button.textContent = 'Liked';
                button.classList.add('active');
            } catch (error) {
                button.disabled = false;
                button.textContent = originalLabel;
                showComposerError(error.message || 'Unable to like this post');
                return;
            }

            // Keep the liked state visible, but avoid duplicate likes from accidental clicks.
            button.disabled = true;
        }

        function renderPost(postInput) {
            const post = getCanonicalPost(postInput);
            if (!post) {
                return null;
            }

            const author = getAuthor(post);
            const text = getPostText(post);
            const timestamp = formatTimestamp(getPostTime(post));
            const initials = getInitials(author);
            const uri = getPostUri(post);

            const container = document.createElement('article');
            container.className = 'skylab-post';
            if (uri) {
                container.dataset.uri = uri;
            }
            if (post.cid) {
                container.dataset.cid = post.cid;
            }

            const headerEl = document.createElement('div');
            headerEl.className = 'skylab-post-header';

            const avatarEl = document.createElement('div');
            avatarEl.className = 'skylab-post-avatar';
            avatarEl.textContent = initials;

            const metaEl = document.createElement('div');
            metaEl.className = 'skylab-post-meta';

            const authorEl = document.createElement('div');
            authorEl.className = 'skylab-post-author';
            authorEl.textContent = getDisplayName(author);

            const handleEl = document.createElement('div');
            handleEl.className = 'skylab-post-handle';
            handleEl.textContent = getHandle(author);

            const timeEl = document.createElement('time');
            timeEl.className = 'skylab-post-time';
            timeEl.textContent = timestamp;
            if (post?.record?.createdAt || post?.createdAt || post?.indexedAt) {
                timeEl.dateTime = post.record?.createdAt || post.createdAt || post.indexedAt;
            }

            metaEl.appendChild(authorEl);
            if (handleEl.textContent) {
                metaEl.appendChild(handleEl);
            }
            if (timeEl.textContent) {
                metaEl.appendChild(timeEl);
            }

            headerEl.appendChild(avatarEl);
            headerEl.appendChild(metaEl);

            const textEl = document.createElement('div');
            textEl.className = 'skylab-post-text';
            textEl.textContent = text;

            const actionsEl = document.createElement('div');
            actionsEl.className = 'skylab-post-actions';

            const likeButton = makeActionButton('Like', 'skylab-post-like');
            likeButton.addEventListener('click', () => likePost(post, likeButton));

            const repostButton = makeActionButton('Repost', 'skylab-post-repost');
            repostButton.title = 'Repost coming soon';
            repostButton.addEventListener('click', () => {
                console.info('Repost is not implemented yet for this panel.');
            });

            const replyButton = makeActionButton('Reply', 'skylab-post-reply');
            replyButton.addEventListener('click', () => focusReplyComposer(post));

            actionsEl.appendChild(likeButton);
            actionsEl.appendChild(repostButton);
            actionsEl.appendChild(replyButton);

            container.appendChild(headerEl);
            container.appendChild(textEl);
            container.appendChild(actionsEl);

            return container;
        }

        function insertPost(postInput, { prepend = false } = {}) {
            const post = getCanonicalPost(postInput);
            if (!post) {
                return;
            }

            const uri = getPostUri(post);
            if (uri && seenUris.has(uri)) {
                return;
            }

            const postEl = renderPost(post);
            if (!postEl) {
                return;
            }

            if (uri) {
                seenUris.add(uri);
            }

            // Remove placeholder states before showing the first real post.
            if (feedEl.firstElementChild?.classList.contains('skylab-empty-state')) {
                clearFeed();
            }

            if (prepend) {
                feedEl.insertBefore(postEl, feedEl.firstChild);
            } else {
                feedEl.appendChild(postEl);
            }
        }

        function renderPosts(posts, { prepend = false, replace = false } = {}) {
            if (replace) {
                clearFeed();
            }

            const list = Array.isArray(posts) ? posts : [];
            if (list.length === 0 && !prepend && replace) {
                showFeedMessage('No posts found.');
                return;
            }

            const fragment = document.createDocumentFragment();
            const normalizedPosts = [];

            for (const item of list) {
                const post = getCanonicalPost(item);
                if (!post) {
                    continue;
                }

                const uri = getPostUri(post);
                if (uri && seenUris.has(uri)) {
                    continue;
                }

                const postEl = renderPost(post);
                if (!postEl) {
                    continue;
                }

                if (uri) {
                    seenUris.add(uri);
                }

                normalizedPosts.push(postEl);
            }

            if (normalizedPosts.length === 0) {
                if (replace) {
                    showFeedMessage('No posts found.');
                }
                return;
            }

            for (const postEl of normalizedPosts) {
                fragment.appendChild(postEl);
            }

            if (prepend) {
                feedEl.insertBefore(fragment, feedEl.firstChild);
            } else {
                feedEl.appendChild(fragment);
            }
        }

        // --------------------------------------------------------------------
        // Timeline loading
        // --------------------------------------------------------------------

        async function loadTimeline() {
            if (!bridge.auth?.did) {
                clearFeed();
                showFeedMessage('Sign in to see your timeline');
                return;
            }

            if (loading) {
                return;
            }

            loading = true;
            const requestVersion = ++timelineLoadVersion;
            if (refreshEl) {
                refreshEl.disabled = true;
            }

            showFeedMessage('Loading timeline…');

            try {
                const resp = await bridge.xrpc(
                    'app.bsky.feed.getTimeline',
                    { limit: 25 },
                    null,
                    { service: 'appview', auth: true },
                );

                if (!resp.ok) {
                    throw new Error(extractErrorMessage(resp.data, 'Unable to load timeline'));
                }

                if (requestVersion !== timelineLoadVersion || !bridge.auth?.did) {
                    return;
                }

                const feed = Array.isArray(resp.data?.feed)
                    ? resp.data.feed
                    : Array.isArray(resp.data?.posts)
                        ? resp.data.posts
                        : [];

                renderPosts(feed, { replace: true });
            } catch (error) {
                clearFeed();
                showFeedMessage(error.message || 'Unable to load timeline');
            } finally {
                loading = false;
                if (refreshEl) {
                    refreshEl.disabled = false;
                }
            }
        }

        // --------------------------------------------------------------------
        // Composer wiring
        // --------------------------------------------------------------------

        async function submitComposerPost() {
            if (!composerTextEl) {
                return;
            }

            const text = composerTextEl.value.trim();
            if (!text) {
                showComposerError('Write a post before publishing.');
                return;
            }

            if (!bridge.auth?.did) {
                showComposerError('Sign in to post.');
                return;
            }

            clearComposerError();
            if (composerPostEl) {
                composerPostEl.disabled = true;
                composerPostEl.textContent = 'Posting…';
            }

            try {
                const resp = await bridge.xrpc(
                    'com.atproto.repo.createRecord',
                    null,
                    {
                        repo: bridge.auth.did,
                        collection: 'app.bsky.feed.post',
                        rkey: Date.now().toString(),
                        record: {
                            $type: 'app.bsky.feed.post',
                            text,
                            createdAt: new Date().toISOString(),
                        },
                    },
                    { service: 'pds', auth: true },
                );

                if (!resp.ok) {
                    throw new Error(extractErrorMessage(resp.data, 'Unable to publish post'));
                }

                composerTextEl.value = '';
                updateComposerCount();
                clearComposerError();
            } catch (error) {
                showComposerError(error.message || 'Unable to publish post');
            } finally {
                if (composerPostEl) {
                    composerPostEl.disabled = false;
                    composerPostEl.textContent = 'Post';
                }
            }
        }

        if (composerTextEl) {
            composerTextEl.addEventListener('input', () => {
                updateComposerCount();
                clearComposerError();
            });
            updateComposerCount();
        }

        if (composerPostEl) {
            composerPostEl.addEventListener('click', submitComposerPost);
        }

        if (refreshEl) {
            refreshEl.addEventListener('click', loadTimeline);
        }

        // --------------------------------------------------------------------
        // Bridge integrations
        // --------------------------------------------------------------------

        bridge.on('auth_change', (auth) => {
            if (auth?.did) {
                loadTimeline();
            } else {
                timelineLoadVersion++;
                clearFeed();
                showFeedMessage('Sign in to see your timeline');
            }
        });

        bridge.on('firehose_frame', (frame) => {
            // Best-effort support for parsed firehose payloads.
            // The bridge currently emits the raw frame, but future parsers or
            // tests may attach a `post` object or JSON string payload here.
            const candidate = frame?.post
                || frame?.data?.post
                || frame?.record
                || frame?.data?.record
                || frame?.data;

            let post = null;

            if (candidate && typeof candidate === 'string') {
                try {
                    const parsed = JSON.parse(candidate);
                    post = getCanonicalPost(parsed);
                } catch {
                    post = null;
                }
            } else {
                post = getCanonicalPost(candidate);
            }

            if (post?.uri) {
                insertPost(post, { prepend: true });
            }
        });

        // Initial state mirrors the current auth session.
        if (bridge.auth?.did) {
            loadTimeline();
        } else {
            showFeedMessage('Sign in to see your timeline');
        }
    }

    global.initTimelinePanel = initTimelinePanel;

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { initTimelinePanel };
    }
})(typeof window !== 'undefined' ? window : globalThis);
