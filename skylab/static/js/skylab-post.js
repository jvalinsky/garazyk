(function(global) {
    'use strict';

    function getCanonicalPost(item) {
        if (!item) return null;
        if (item.post && (item.post.uri || item.post.cid || item.post.record)) return item.post;
        return item;
    }

    function getAuthor(post) { return post?.author || null; }

    function getDisplayName(author) { return author?.displayName || author?.handle || 'Unknown'; }

    function getHandle(author) { return author?.handle ? '@' + author.handle : ''; }

    function getPostText(post) {
        if (!post) return '';
        if (typeof post.text === 'string') return post.text;
        if (typeof post.record?.text === 'string') return post.record.text;
        return '';
    }

    function getPostTime(post) {
        return post?.record?.createdAt || post?.createdAt || post?.indexedAt || '';
    }

    function formatTimestamp(ts) {
        if (!ts) return '';
        const d = new Date(ts);
        if (isNaN(d.getTime())) return ts;
        return d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
    }

    function getInitials(author) {
        const source = (author?.displayName || author?.handle || '??').trim();
        if (!source) return '??';
        const words = source.replace(/[^\p{L}\p{N}]+/gu, ' ').trim().split(/\s+/).filter(Boolean);
        if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
        if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
        return source.slice(0, 2).toUpperCase();
    }

    function getPostUri(post) { return post?.uri || ''; }

    function parseUri(uri) {
        if (!uri) return null;
        const m = uri.match(/^at:\/\/([^/]+)\/([^/]+)\/(.+)$/);
        if (!m) return null;
        return { did: m[1], collection: m[2], rkey: m[3] };
    }

    function renderPost(postInput, options = {}) {
        const post = getCanonicalPost(postInput);
        if (!post) return null;

        const author = getAuthor(post);
        const text = getPostText(post);
        const ts = formatTimestamp(getPostTime(post));
        const initials = getInitials(author);
        const uri = getPostUri(post);
        const uriParts = parseUri(uri);

        const container = document.createElement('article');
        container.className = 'skylab-post';
        if (options.threadDepth) {
            container.style.marginLeft = (options.threadDepth * 24) + 'px';
            container.style.borderLeft = '2px solid var(--separator-color-secondary)';
        }
        if (uri) container.dataset.uri = uri;
        if (post.cid) container.dataset.cid = post.cid;

        const header = document.createElement('div');
        header.className = 'skylab-post-header';

        const avatar = document.createElement('div');
        avatar.className = 'skylab-post-avatar';
        avatar.textContent = initials;

        const meta = document.createElement('div');
        meta.className = 'skylab-post-meta';

        const authorLink = document.createElement('a');
        authorLink.className = 'skylab-post-author';
        authorLink.textContent = getDisplayName(author);
        authorLink.href = '#/profile/' + (author?.handle || author?.did || '');
        authorLink.addEventListener('click', (e) => {
            e.stopPropagation();
        });

        const handleEl = document.createElement('span');
        handleEl.className = 'skylab-post-handle';
        const handleLink = document.createElement('a');
        handleLink.textContent = getHandle(author);
        handleLink.href = '#/profile/' + (author?.handle || author?.did || '');
        handleLink.className = 'skylab-post-handle-link';
        handleLink.addEventListener('click', (e) => e.stopPropagation());
        handleEl.appendChild(handleLink);

        const timeEl = document.createElement('time');
        timeEl.className = 'skylab-post-time';
        timeEl.textContent = ts;
        if (getPostTime(post)) {
            timeEl.dateTime = getPostTime(post);
        }

        meta.appendChild(authorLink);
        if (handleEl.textContent) meta.appendChild(handleEl);
        if (timeEl.textContent) meta.appendChild(timeEl);
        header.appendChild(avatar);
        header.appendChild(meta);

        const textEl = document.createElement('div');
        textEl.className = 'skylab-post-text';
        textEl.textContent = text;
        if (uriParts && !options.noThreadLink) {
            textEl.style.cursor = 'pointer';
            textEl.addEventListener('click', () => {
                const evt = new CustomEvent('skylab-navigate', {
                    detail: { route: 'thread', params: [uriParts.did, uriParts.rkey] },
                    bubbles: true,
                });
                container.dispatchEvent(evt);
            });
        }

        const actions = document.createElement('div');
        actions.className = 'skylab-post-actions';

        if (options.showActions !== false) {
            const likeBtn = document.createElement('button');
            likeBtn.className = 'skylab-btn skylab-btn-sm skylab-post-action';
            likeBtn.textContent = 'Like';
            likeBtn.dataset.action = 'like';

            const replyBtn = document.createElement('button');
            replyBtn.className = 'skylab-btn skylab-btn-sm skylab-post-action';
            replyBtn.textContent = 'Reply';
            replyBtn.dataset.action = 'reply';

            const profileBtn = document.createElement('button');
            profileBtn.className = 'skylab-btn skylab-btn-sm skylab-post-action';
            profileBtn.textContent = 'Profile';
            profileBtn.dataset.action = 'profile';
            profileBtn.addEventListener('click', () => {
                const evt = new CustomEvent('skylab-navigate', {
                    detail: { route: 'profile', params: [author?.handle || author?.did || ''] },
                    bubbles: true,
                });
                container.dispatchEvent(evt);
            });

            actions.appendChild(likeBtn);
            actions.appendChild(replyBtn);
            actions.appendChild(profileBtn);
        }

        container.appendChild(header);
        container.appendChild(textEl);
        container.appendChild(actions);

        return container;
    }

    global.SkyLabPost = {
        renderPost,
        getCanonicalPost,
        getAuthor,
        getDisplayName,
        getHandle,
        getPostText,
        getPostTime,
        getPostUri,
        parseUri,
        formatTimestamp,
    };
})(typeof window !== 'undefined' ? window : globalThis);
