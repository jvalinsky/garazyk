// Record type renderers for ATProto record types

export const RecordRenderers = {
    // Render a record based on its $type
    render(record, options = {}) {
        const value = record.value || record;
        const type = value['$type'] || record.collection;
        
        const renderer = this.renderers[type];
        if (renderer) {
            return renderer(record, value, options);
        }
        return this.renderGeneric(record, value, options);
    },

    // Format a timestamp nicely
    formatTime(isoString) {
        if (!isoString) return '';
        try {
            const date = new Date(isoString);
            return date.toLocaleString();
        } catch {
            return isoString;
        }
    },

    // Format a DID as a shorter display string
    formatDid(did) {
        if (!did) return '';
        if (did.length > 30) {
            return did.substring(0, 20) + '...' + did.substring(did.length - 8);
        }
        return did;
    },

    // Format an AT URI
    formatUri(uri) {
        if (!uri) return '';
        // at://did:plc:xxx/collection/rkey
        const match = uri.match(/^at:\/\/([^\/]+)\/([^\/]+)\/(.+)$/);
        if (match) {
            return `<span class="uri-did">${this.formatDid(match[1])}</span>/<span class="uri-collection">${match[2]}</span>/<span class="uri-rkey">${match[3]}</span>`;
        }
        return escapeHtml(uri);
    },

    // Render facets (mentions, links, tags) in text
    renderTextWithFacets(text, facets) {
        if (!facets || facets.length === 0) {
            return escapeHtml(text);
        }

        // Sort facets by byte start position
        const sorted = [...facets].sort((a, b) => 
            (a.index?.byteStart || 0) - (b.index?.byteStart || 0)
        );

        // Convert text to bytes for proper slicing
        const encoder = new TextEncoder();
        const decoder = new TextDecoder();
        const bytes = encoder.encode(text);
        
        let result = '';
        let lastEnd = 0;

        for (const facet of sorted) {
            const start = facet.index?.byteStart || 0;
            const end = facet.index?.byteEnd || 0;
            
            // Add text before this facet
            if (start > lastEnd) {
                result += escapeHtml(decoder.decode(bytes.slice(lastEnd, start)));
            }

            const facetText = decoder.decode(bytes.slice(start, end));
            const feature = facet.features?.[0];

            if (feature) {
                if (feature['$type'] === 'app.bsky.richtext.facet#mention') {
                    result += `<a class="mention" href="#" data-did="${escapeHtml(feature.did)}">@${escapeHtml(facetText.replace('@', ''))}</a>`;
                } else if (feature['$type'] === 'app.bsky.richtext.facet#link') {
                    result += `<a class="link" href="${escapeHtml(feature.uri)}" target="_blank" rel="noopener">${escapeHtml(facetText)}</a>`;
                } else if (feature['$type'] === 'app.bsky.richtext.facet#tag') {
                    result += `<span class="hashtag">#${escapeHtml(feature.tag)}</span>`;
                } else {
                    result += escapeHtml(facetText);
                }
            } else {
                result += escapeHtml(facetText);
            }

            lastEnd = end;
        }

        // Add remaining text
        if (lastEnd < bytes.length) {
            result += escapeHtml(decoder.decode(bytes.slice(lastEnd)));
        }

        return result;
    },

    // Generic renderer for unknown types
    renderGeneric(record, value, options) {
        const type = value['$type'] || record.collection || 'Unknown';
        return `
            <div class="record-card record-generic">
                <div class="record-header">
                    <span class="record-type">${escapeHtml(type)}</span>
                    <span class="record-time">${this.formatTime(value.createdAt)}</span>
                </div>
                <div class="record-body">
                    <table class="record-fields">
                        ${Object.entries(value)
                            .filter(([k]) => k !== '$type' && k !== 'createdAt')
                            .map(([k, v]) => `
                                <tr>
                                    <td class="field-name">${escapeHtml(k)}</td>
                                    <td class="field-value">${this.renderValue(v)}</td>
                                </tr>
                            `).join('')}
                    </table>
                </div>
                ${this.renderRecordMeta(record)}
            </div>
        `;
    },

    // Render a value (handles nested objects)
    renderValue(value) {
        if (value === null || value === undefined) {
            return '<span class="null">null</span>';
        }
        if (typeof value === 'string') {
            if (value.startsWith('at://')) {
                return `<a class="at-uri" href="#" onclick="window.viewRecordDetail('${escapeHtml(value)}'); return false;">${escapeHtml(value)}</a>`;
            }
            if (value.startsWith('did:')) {
                return `<span class="did">${escapeHtml(value)}</span>`;
            }
            if (value.match(/^https?:\/\//)) {
                return `<a href="${escapeHtml(value)}" target="_blank" rel="noopener">${escapeHtml(value)}</a>`;
            }
            return escapeHtml(value);
        }
        if (typeof value === 'number' || typeof value === 'boolean') {
            return `<span class="primitive">${value}</span>`;
        }
        if (Array.isArray(value)) {
            if (value.length === 0) return '<span class="empty">[]</span>';
            return `<span class="array">[${value.length} items]</span>`;
        }
        if (typeof value === 'object') {
            // Check for blob reference
            if (value['$type'] === 'blob' || value.ref) {
                return `<span class="blob">📎 Blob (${value.mimeType || 'unknown type'})</span>`;
            }
            return `<span class="object">{...}</span>`;
        }
        return escapeHtml(String(value));
    },

    // Render record metadata (URI, CID)
    renderRecordMeta(record) {
        return `
            <div class="record-meta">
                <div class="meta-item">
                    <span class="meta-label">URI:</span>
                    <code class="meta-value">${escapeHtml(record.uri || '')}</code>
                </div>
                <div class="meta-item">
                    <span class="meta-label">CID:</span>
                    <code class="meta-value">${escapeHtml(record.cid || '')}</code>
                </div>
            </div>
        `;
    },

    renderers: {
        // Post renderer
        'app.bsky.feed.post': (record, value, options) => {
            const text = RecordRenderers.renderTextWithFacets(value.text || '', value.facets);
            const hasEmbed = value.embed != null;
            const hasReply = value.reply != null;
            
            let embedHtml = '';
            if (value.embed) {
                embedHtml = RecordRenderers.renderEmbed(value.embed);
            }

            let replyHtml = '';
            if (value.reply) {
                replyHtml = `
                    <div class="post-reply-info">
                        <span class="reply-icon">↩️</span>
                        Reply to: <a href="#" onclick="window.viewRecordDetail('${escapeHtml(value.reply.parent?.uri || '')}'); return false;">
                            ${RecordRenderers.formatDid(value.reply.parent?.uri?.split('/')[2] || '')}
                        </a>
                    </div>
                `;
            }

            return `
                <div class="record-card record-post">
                    <div class="record-header">
                        <span class="record-type">📝 Post</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    ${replyHtml}
                    <div class="post-text">${text}</div>
                    ${embedHtml}
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // Profile renderer
        'app.bsky.actor.profile': (record, value, options) => {
            let avatarHtml = '';
            if (value.avatar) {
                avatarHtml = `<div class="profile-avatar">📷 Avatar attached</div>`;
            }
            let bannerHtml = '';
            if (value.banner) {
                bannerHtml = `<div class="profile-banner">🖼️ Banner attached</div>`;
            }

            return `
                <div class="record-card record-profile">
                    <div class="record-header">
                        <span class="record-type">👤 Profile</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="profile-content">
                        ${avatarHtml}
                        ${bannerHtml}
                        <div class="profile-name">
                            <strong>${escapeHtml(value.displayName || '(no display name)')}</strong>
                        </div>
                        <div class="profile-description">${escapeHtml(value.description || '(no description)')}</div>
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // Like renderer
        'app.bsky.feed.like': (record, value, options) => {
            return `
                <div class="record-card record-like">
                    <div class="record-header">
                        <span class="record-type">❤️ Like</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="like-target">
                        <span class="target-label">Liked:</span>
                        <a href="#" onclick="window.viewRecordDetail('${escapeHtml(value.subject?.uri || '')}'); return false;">
                            ${escapeHtml(value.subject?.uri || 'unknown')}
                        </a>
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // Repost renderer
        'app.bsky.feed.repost': (record, value, options) => {
            return `
                <div class="record-card record-repost">
                    <div class="record-header">
                        <span class="record-type">🔁 Repost</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="repost-target">
                        <span class="target-label">Reposted:</span>
                        <a href="#" onclick="window.viewRecordDetail('${escapeHtml(value.subject?.uri || '')}'); return false;">
                            ${escapeHtml(value.subject?.uri || 'unknown')}
                        </a>
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // Follow renderer
        'app.bsky.graph.follow': (record, value, options) => {
            return `
                <div class="record-card record-follow">
                    <div class="record-header">
                        <span class="record-type">➕ Follow</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="follow-target">
                        <span class="target-label">Following:</span>
                        <span class="did">${escapeHtml(value.subject || 'unknown')}</span>
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // Block renderer
        'app.bsky.graph.block': (record, value, options) => {
            return `
                <div class="record-card record-block">
                    <div class="record-header">
                        <span class="record-type">🚫 Block</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="block-target">
                        <span class="target-label">Blocked:</span>
                        <span class="did">${escapeHtml(value.subject || 'unknown')}</span>
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // List renderer
        'app.bsky.graph.list': (record, value, options) => {
            const purposeMap = {
                'app.bsky.graph.defs#curatelist': '📋 Curation List',
                'app.bsky.graph.defs#modlist': '🛡️ Moderation List'
            };
            const purpose = purposeMap[value.purpose] || value.purpose || 'List';

            return `
                <div class="record-card record-list">
                    <div class="record-header">
                        <span class="record-type">${purpose}</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="list-content">
                        <div class="list-name"><strong>${escapeHtml(value.name || '(unnamed)')}</strong></div>
                        <div class="list-description">${escapeHtml(value.description || '')}</div>
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // List item renderer
        'app.bsky.graph.listitem': (record, value, options) => {
            return `
                <div class="record-card record-listitem">
                    <div class="record-header">
                        <span class="record-type">📌 List Item</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="listitem-content">
                        <div class="listitem-subject">
                            <span class="target-label">Subject:</span>
                            <span class="did">${escapeHtml(value.subject || 'unknown')}</span>
                        </div>
                        <div class="listitem-list">
                            <span class="target-label">In list:</span>
                            <a href="#" onclick="window.viewRecordDetail('${escapeHtml(value.list || '')}'); return false;">
                                ${escapeHtml(value.list || 'unknown')}
                            </a>
                        </div>
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },

        // Threadgate renderer
        'app.bsky.feed.threadgate': (record, value, options) => {
            let rulesHtml = '';
            if (value.allow && value.allow.length > 0) {
                const rules = value.allow.map(rule => {
                    if (rule['$type'] === 'app.bsky.feed.threadgate#mentionRule') {
                        return '👥 Mentioned users';
                    }
                    if (rule['$type'] === 'app.bsky.feed.threadgate#followingRule') {
                        return '👤 Users you follow';
                    }
                    if (rule['$type'] === 'app.bsky.feed.threadgate#listRule') {
                        return `📋 List: ${rule.list || 'unknown'}`;
                    }
                    return rule['$type'] || 'Unknown rule';
                });
                rulesHtml = `<div class="threadgate-rules">Allow: ${rules.join(', ')}</div>`;
            }

            return `
                <div class="record-card record-threadgate">
                    <div class="record-header">
                        <span class="record-type">🔒 Threadgate</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="threadgate-content">
                        <div class="threadgate-post">
                            <span class="target-label">For post:</span>
                            <a href="#" onclick="window.viewRecordDetail('${escapeHtml(value.post || '')}'); return false;">
                                ${escapeHtml(value.post || 'unknown')}
                            </a>
                        </div>
                        ${rulesHtml}
                    </div>
                    ${RecordRenderers.renderRecordMeta(record)}
                </div>
            `;
        },
    },

    // Render embeds (images, external links, quotes, etc.)
    renderEmbed(embed) {
        if (!embed) return '';

        const type = embed['$type'];

        // Images
        if (type === 'app.bsky.embed.images' || embed.images) {
            const images = embed.images || [];
            return `
                <div class="embed embed-images">
                    <div class="embed-label">🖼️ ${images.length} image(s) attached</div>
                    ${images.map(img => `
                        <div class="embed-image-info">
                            ${img.alt ? `<span class="image-alt">Alt: ${escapeHtml(img.alt)}</span>` : ''}
                        </div>
                    `).join('')}
                </div>
            `;
        }

        // External link
        if (type === 'app.bsky.embed.external' || embed.external) {
            const ext = embed.external || {};
            return `
                <div class="embed embed-external">
                    <div class="embed-label">🔗 External Link</div>
                    <div class="external-card">
                        <div class="external-title">${escapeHtml(ext.title || '')}</div>
                        <div class="external-description">${escapeHtml(ext.description || '')}</div>
                        <a href="${escapeHtml(ext.uri || '')}" target="_blank" rel="noopener" class="external-uri">
                            ${escapeHtml(ext.uri || '')}
                        </a>
                    </div>
                </div>
            `;
        }

        // Record embed (quote)
        if (type === 'app.bsky.embed.record' || embed.record) {
            const rec = embed.record || {};
            return `
                <div class="embed embed-record">
                    <div class="embed-label">💬 Quote</div>
                    <div class="quote-card">
                        <a href="#" onclick="window.viewRecordDetail('${escapeHtml(rec.uri || '')}'); return false;">
                            ${escapeHtml(rec.uri || 'unknown')}
                        </a>
                    </div>
                </div>
            `;
        }

        // Record with media
        if (type === 'app.bsky.embed.recordWithMedia') {
            let html = '';
            if (embed.record) {
                html += this.renderEmbed({ ...embed.record, '$type': 'app.bsky.embed.record' });
            }
            if (embed.media) {
                html += this.renderEmbed(embed.media);
            }
            return html;
        }

        // Video
        if (type === 'app.bsky.embed.video' || embed.video) {
            return `
                <div class="embed embed-video">
                    <div class="embed-label">🎬 Video attached</div>
                </div>
            `;
        }

        return `<div class="embed embed-unknown">📎 Embed: ${escapeHtml(type || 'unknown')}</div>`;
    }
};

// Helper function (needs to be available)
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
