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

    // Extract DID from an AT URI (at://did:xxx/collection/rkey)
    extractDidFromUri(uri) {
        if (!uri) return null;
        const match = uri.match(/^at:\/\/([^\/]+)/);
        return match ? match[1] : null;
    },

    // Extract blob CID from a blob reference object
    // Handles both formats:
    //   { "$type": "blob", "ref": { "$link": "bafyrei..." }, ... }
    //   { "cid": "bafyrei...", ... }
    extractBlobCid(blob) {
        if (!blob) return null;
        // New format with $link
        if (blob.ref && blob.ref['$link']) {
            return blob.ref['$link'];
        }
        // Direct CID field
        if (blob.cid) {
            return blob.cid;
        }
        // Legacy format
        if (blob['$link']) {
            return blob['$link'];
        }
        return null;
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
        const did = this.extractDidFromUri(record.uri);
        
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
                                    <td class="field-value">${this.renderValue(v, did)}</td>
                                </tr>
                            `).join('')}
                    </table>
                </div>
                ${this.renderRecordMeta(record)}
            </div>
        `;
    },

    // Render a value (handles nested objects)
    // Render a value with optional DID context for blob links
    renderValue(value, did = null) {
        if (value === null || value === undefined) {
            return '<span class="null">null</span>';
        }
        if (typeof value === 'string') {
            if (value.startsWith('at://')) {
                return `<a class="at-uri" href="#" onclick="window.viewRecordDetail('${escapeHtml(value)}'); return false;">${escapeHtml(value)}</a>`;
            }
            if (value.startsWith('did:')) {
                return `<a class="did" href="#/${escapeHtml(value)}">${escapeHtml(value)}</a>`;
            }
            if (value.match(/^https?:\/\//)) {
                return `<a href="${escapeHtml(value)}" target="_blank" rel="noopener">${escapeHtml(value)}</a>`;
            }
            // CID-like strings
            if (value.match(/^b[a-z2-7]{50,}/i)) {
                if (did) {
                    return `<a class="cid-link" href="#/${did}/blobs/${escapeHtml(value)}">${escapeHtml(value.substring(0, 20))}...</a>`;
                }
                return `<code class="cid">${escapeHtml(value.substring(0, 20))}...</code>`;
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
                const cid = this.extractBlobCid(value);
                const mimeType = value.mimeType || 'unknown';
                const size = value.size;
                const icon = this.getBlobIcon(mimeType);
                
                if (cid && did) {
                    const detailUrl = `#/${did}/blobs/${cid}`;
                    return `<a href="${detailUrl}" class="record-blob-ref">
                        <span class="blob-icon">${icon}</span>
                        <span class="blob-type">${escapeHtml(mimeType)}</span>
                        ${size ? `<span class="blob-size">${this.formatFileSize(size)}</span>` : ''}
                    </a>`;
                }
                return `<span class="record-blob-ref">
                    <span class="blob-icon">${icon}</span>
                    <span class="blob-type">${escapeHtml(mimeType)}</span>
                    ${size ? `<span class="blob-size">${this.formatFileSize(size)}</span>` : ''}
                </span>`;
            }
            return `<span class="object">{...}</span>`;
        }
        return escapeHtml(String(value));
    },

    // Get appropriate icon for blob MIME type
    getBlobIcon(mimeType) {
        if (!mimeType) return '📎';
        if (mimeType.startsWith('image/')) return '🖼️';
        if (mimeType.startsWith('video/')) return '🎬';
        if (mimeType.startsWith('audio/')) return '🎵';
        if (mimeType === 'application/pdf') return '📄';
        if (mimeType.startsWith('text/') || mimeType === 'application/json') return '📝';
        if (mimeType.includes('zip') || mimeType.includes('tar') || mimeType.includes('compressed')) return '📦';
        return '📎';
    },

    // Format file size (duplicated here for convenience)
    formatFileSizeShort(bytes) {
        if (!bytes) return '';
        if (bytes < 1024) return `${bytes}B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)}KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
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
            const did = RecordRenderers.extractDidFromUri(record.uri);
            const text = RecordRenderers.renderTextWithFacets(value.text || '', value.facets);
            const hasEmbed = value.embed != null;
            const hasReply = value.reply != null;
            
            let embedHtml = '';
            if (value.embed) {
                embedHtml = RecordRenderers.renderEmbed(value.embed, did);
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
            // Extract DID from record URI (at://did:plc:xxx/collection/rkey)
            const did = RecordRenderers.extractDidFromUri(record.uri);
            
            // Helper to format blob size
            const formatSize = (size) => {
                if (!size) return '';
                if (size < 1024) return `${size} B`;
                if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
                return `${(size / (1024 * 1024)).toFixed(1)} MB`;
            };
            
            // Helper to create error HTML for failed images
            const createImageError = (type, cid) => {
                const icon = type === 'banner' ? '🖼️' : '📷';
                const cssClass = type === 'banner' ? 'banner-load-error' : 'avatar-load-error';
                return `<div class="image-load-error ${cssClass}">
                    <span class="error-icon">${icon}</span>
                    <span class="error-text">${type === 'banner' ? 'Banner' : 'Avatar'} failed to load</span>
                    ${cid ? `<span class="error-cid">${cid.substring(0, 20)}...</span>` : ''}
                </div>`;
            };
            
            const hasBanner = value.banner != null;
            const hasAvatar = value.avatar != null;
            const bannerCid = hasBanner ? RecordRenderers.extractBlobCid(value.banner) : null;
            const avatarCid = hasAvatar ? RecordRenderers.extractBlobCid(value.avatar) : null;
            
            let headerImagesHtml = '';
            
            if (hasBanner || hasAvatar) {
                const bannerUrl = bannerCid && did ? `/xrpc/com.atproto.sync.getBlob?did=${encodeURIComponent(did)}&cid=${encodeURIComponent(bannerCid)}` : null;
                const avatarUrl = avatarCid && did ? `/xrpc/com.atproto.sync.getBlob?did=${encodeURIComponent(did)}&cid=${encodeURIComponent(avatarCid)}` : null;
                const bannerDetailUrl = bannerCid ? `#/${did}/blobs/${bannerCid}` : null;
                const avatarDetailUrl = avatarCid ? `#/${did}/blobs/${avatarCid}` : null;
                
                // Get blob metadata if available
                const bannerMime = value.banner?.mimeType || 'image/*';
                const bannerSize = value.banner?.size;
                const avatarMime = value.avatar?.mimeType || 'image/*';
                const avatarSize = value.avatar?.size;
                
                let bannerHtml = '';
                if (hasBanner) {
                    if (bannerUrl) {
                        bannerHtml = `
                            <div class="profile-banner">
                                <a href="${bannerDetailUrl}" title="View banner blob details">
                                    <img src="${bannerUrl}" alt="Profile banner" class="profile-banner-img" 
                                         onerror="this.parentElement.outerHTML=decodeURIComponent('${encodeURIComponent(createImageError('banner', bannerCid))}')">
                                </a>
                            </div>`;
                    } else {
                        bannerHtml = `<div class="profile-banner">${createImageError('banner', null)}</div>`;
                    }
                }
                
                let avatarHtml = '';
                if (hasAvatar) {
                    if (avatarUrl) {
                        avatarHtml = `
                            <div class="profile-avatar">
                                <a href="${avatarDetailUrl}" title="View avatar blob details">
                                    <img src="${avatarUrl}" alt="Profile avatar" class="profile-avatar-img"
                                         onerror="this.parentElement.outerHTML=decodeURIComponent('${encodeURIComponent(createImageError('avatar', avatarCid))}')">
                                </a>
                            </div>`;
                    } else {
                        avatarHtml = `<div class="profile-avatar">${createImageError('avatar', null)}</div>`;
                    }
                }
                
                // Use combined header layout if we have banner
                if (hasBanner) {
                    headerImagesHtml = `
                        <div class="profile-header-images">
                            ${bannerHtml}
                            ${avatarHtml}
                        </div>`;
                } else if (hasAvatar) {
                    // Avatar only - standalone layout
                    headerImagesHtml = `
                        <div class="profile-avatar-standalone">
                            ${avatarHtml.replace('profile-avatar', 'profile-avatar profile-avatar-standalone')}
                        </div>`;
                }
                
                // Blob metadata section
                let blobMetaHtml = '';
                if (bannerCid || avatarCid) {
                    blobMetaHtml = `<div class="profile-blobs-info" style="margin-top: 15px; padding: 12px; background: #f8f9fa; border-radius: 8px; font-size: 12px;">
                        <div style="font-weight: 600; margin-bottom: 8px; color: #555;">📎 Attached Blobs</div>`;
                    
                    if (bannerCid) {
                        blobMetaHtml += `
                            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 6px; padding: 6px; background: #fff; border-radius: 4px;">
                                <span style="font-size: 16px;">🖼️</span>
                                <div style="flex: 1; min-width: 0;">
                                    <div style="font-weight: 500;">Banner</div>
                                    <div style="font-size: 10px; color: #888; font-family: monospace; overflow: hidden; text-overflow: ellipsis;">${bannerCid}</div>
                                    <div class="profile-blob-meta">
                                        <span>📄 ${bannerMime}</span>
                                        ${bannerSize ? `<span>📦 ${formatSize(bannerSize)}</span>` : ''}
                                    </div>
                                </div>
                                <a href="${bannerDetailUrl}" style="padding: 4px 8px; background: var(--link-color); color: #fff; border-radius: 4px; text-decoration: none; font-size: 11px;">View</a>
                            </div>`;
                    }
                    
                    if (avatarCid) {
                        blobMetaHtml += `
                            <div style="display: flex; align-items: center; gap: 8px; padding: 6px; background: #fff; border-radius: 4px;">
                                <span style="font-size: 16px;">📷</span>
                                <div style="flex: 1; min-width: 0;">
                                    <div style="font-weight: 500;">Avatar</div>
                                    <div style="font-size: 10px; color: #888; font-family: monospace; overflow: hidden; text-overflow: ellipsis;">${avatarCid}</div>
                                    <div class="profile-blob-meta">
                                        <span>📄 ${avatarMime}</span>
                                        ${avatarSize ? `<span>📦 ${formatSize(avatarSize)}</span>` : ''}
                                    </div>
                                </div>
                                <a href="${avatarDetailUrl}" style="padding: 4px 8px; background: var(--link-color); color: #fff; border-radius: 4px; text-decoration: none; font-size: 11px;">View</a>
                            </div>`;
                    }
                    
                    blobMetaHtml += `</div>`;
                }
                
                headerImagesHtml += blobMetaHtml;
            }

            return `
                <div class="record-card record-profile">
                    <div class="record-header">
                        <span class="record-type">👤 Profile</span>
                        <span class="record-time">${RecordRenderers.formatTime(value.createdAt)}</span>
                    </div>
                    <div class="profile-content">
                        ${headerImagesHtml}
                        <div class="profile-name" style="margin-top: ${hasBanner ? '0' : '10px'};">
                            <strong style="font-size: 18px;">${escapeHtml(value.displayName || '(no display name)')}</strong>
                        </div>
                        <div class="profile-description" style="margin-top: 8px; color: #555; line-height: 1.5;">${escapeHtml(value.description || '(no description)')}</div>
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

    // Helper to format file size
    formatFileSize(bytes) {
        if (!bytes) return '';
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    },

    // Render embeds (images, external links, quotes, etc.)
    renderEmbed(embed, did) {
        if (!embed) return '';

        const type = embed['$type'];

        // Images
        if (type === 'app.bsky.embed.images' || embed.images) {
            const images = embed.images || [];
            return `
                <div class="embed embed-images">
                    <div class="embed-label">🖼️ ${images.length} image(s) attached</div>
                    <div class="embed-images-grid">
                        ${images.map((img, index) => {
                            const imgCid = RecordRenderers.extractBlobCid(img.image);
                            const mimeType = img.image?.mimeType || 'image/*';
                            const size = img.image?.size;
                            const aspectRatio = img.aspectRatio;
                            
                            if (imgCid && did) {
                                const imgUrl = `/xrpc/com.atproto.sync.getBlob?did=${encodeURIComponent(did)}&cid=${encodeURIComponent(imgCid)}`;
                                const detailUrl = `#/${did}/blobs/${imgCid}`;
                                return `
                                    <div class="embed-image-item">
                                        <a href="${detailUrl}" title="View image blob details">
                                            <img src="${imgUrl}" alt="${escapeHtml(img.alt || 'Embedded image')}" class="embed-image" 
                                                 onerror="this.outerHTML='<div class=image-error><span style=font-size:24px>🖼️</span><br>Image failed to load</div>'">
                                        </a>
                                        ${img.alt ? `<div class="image-alt">📝 ${escapeHtml(img.alt)}</div>` : ''}
                                        <div class="blob-meta">
                                            📄 ${mimeType}${size ? ` · 📦 ${RecordRenderers.formatFileSize(size)}` : ''}${aspectRatio ? ` · 📐 ${aspectRatio.width}×${aspectRatio.height}` : ''}
                                        </div>
                                        <div class="blob-link"><a href="${detailUrl}">🔍 View blob details</a></div>
                                    </div>
                                `;
                            }
                            return `
                                <div class="embed-image-item" style="background: #f5f5f5;">
                                    <div class="image-error">
                                        <span style="font-size:24px">📷</span><br>
                                        Image attached
                                        ${img.alt ? `<br><span style="font-size:11px;font-style:italic">Alt: ${escapeHtml(img.alt)}</span>` : ''}
                                    </div>
                                </div>
                            `;
                        }).join('')}
                    </div>
                </div>
            `;
        }

        // External link
        if (type === 'app.bsky.embed.external' || embed.external) {
            const ext = embed.external || {};
            const thumbCid = ext.thumb ? RecordRenderers.extractBlobCid(ext.thumb) : null;
            const thumbMime = ext.thumb?.mimeType || 'image/*';
            const thumbSize = ext.thumb?.size;
            
            let thumbHtml = '';
            if (thumbCid && did) {
                const thumbUrl = `/xrpc/com.atproto.sync.getBlob?did=${encodeURIComponent(did)}&cid=${encodeURIComponent(thumbCid)}`;
                const thumbDetailUrl = `#/${did}/blobs/${thumbCid}`;
                thumbHtml = `
                    <div class="external-thumb">
                        <a href="${thumbDetailUrl}" title="View thumbnail blob" onclick="event.stopPropagation()">
                            <img src="${thumbUrl}" alt="Link thumbnail" class="external-thumb-img"
                                 onerror="this.parentElement.parentElement.innerHTML='<div class=thumb-placeholder>🖼️</div>'">
                        </a>
                        <div class="thumb-blob-info">
                            <a href="${thumbDetailUrl}" onclick="event.stopPropagation()">🔍 Thumb</a>
                            <span>📄 ${thumbMime}</span>
                            ${thumbSize ? `<span>📦 ${RecordRenderers.formatFileSize(thumbSize)}</span>` : ''}
                        </div>
                    </div>`;
            }
            
            // Try to determine link type from URL
            const uri = ext.uri || '';
            let linkIcon = '🔗';
            let linkType = 'Link';
            if (uri.includes('youtube.com') || uri.includes('youtu.be')) {
                linkIcon = '▶️'; linkType = 'YouTube';
            } else if (uri.includes('twitter.com') || uri.includes('x.com')) {
                linkIcon = '🐦'; linkType = 'Twitter/X';
            } else if (uri.includes('github.com')) {
                linkIcon = '🐙'; linkType = 'GitHub';
            } else if (uri.includes('wikipedia.org')) {
                linkIcon = '📖'; linkType = 'Wikipedia';
            } else if (uri.includes('spotify.com')) {
                linkIcon = '🎵'; linkType = 'Spotify';
            } else if (uri.includes('soundcloud.com')) {
                linkIcon = '🌊'; linkType = 'SoundCloud';
            } else if (uri.includes('twitch.tv')) {
                linkIcon = '🟪'; linkType = 'Twitch';
            } else if (uri.includes('reddit.com')) {
                linkIcon = '🤖'; linkType = 'Reddit';
            } else if (uri.includes('instagram.com')) {
                linkIcon = '📷'; linkType = 'Instagram';
            } else if (uri.includes('tiktok.com')) {
                linkIcon = '🎬'; linkType = 'TikTok';
            }
            
            return `
                <div class="embed embed-external">
                    <div class="embed-label">${linkIcon} ${linkType}</div>
                    <div class="external-card">
                        ${thumbHtml}
                        <div class="external-content">
                            <div class="external-title">${escapeHtml(ext.title || '(no title)')}</div>
                            <div class="external-description">${escapeHtml(ext.description || '')}</div>
                            <a href="${escapeHtml(uri)}" target="_blank" rel="noopener" class="external-uri">
                                ${escapeHtml(uri)}
                            </a>
                        </div>
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
                html += this.renderEmbed({ ...embed.record, '$type': 'app.bsky.embed.record' }, did);
            }
            if (embed.media) {
                html += this.renderEmbed(embed.media, did);
            }
            return html;
        }

        // Video
        if (type === 'app.bsky.embed.video' || embed.video) {
            const video = embed.video || embed;
            const videoCid = RecordRenderers.extractBlobCid(video);
            const videoMime = video.mimeType || 'video/*';
            const videoSize = video.size;
            const aspectRatio = embed.aspectRatio || video.aspectRatio;
            const alt = embed.alt || '';
            const thumbCid = embed.thumb ? RecordRenderers.extractBlobCid(embed.thumb) : null;
            
            let videoHtml = '';
            if (videoCid && did) {
                const videoUrl = `/xrpc/com.atproto.sync.getBlob?did=${encodeURIComponent(did)}&cid=${encodeURIComponent(videoCid)}`;
                const videoDetailUrl = `#/${did}/blobs/${videoCid}`;
                
                // Video player with poster from thumb if available
                let posterAttr = '';
                if (thumbCid) {
                    const thumbUrl = `/xrpc/com.atproto.sync.getBlob?did=${encodeURIComponent(did)}&cid=${encodeURIComponent(thumbCid)}`;
                    posterAttr = `poster="${thumbUrl}"`;
                }
                
                videoHtml = `
                    <div class="embed-video-player">
                        <video src="${videoUrl}" ${posterAttr} controls preload="metadata" class="embed-video-element"
                               onerror="this.outerHTML='<div class=video-error>🎬 Video failed to load</div>'">
                            Your browser doesn't support video playback.
                        </video>
                    </div>
                    ${alt ? `<div class="video-alt">📝 ${escapeHtml(alt)}</div>` : ''}
                    <div class="video-meta">
                        <span>🎬 ${videoMime}</span>
                        ${videoSize ? `<span>📦 ${RecordRenderers.formatFileSize(videoSize)}</span>` : ''}
                        ${aspectRatio ? `<span>📐 ${aspectRatio.width}×${aspectRatio.height}</span>` : ''}
                    </div>
                    <div class="video-blob-links">
                        <a href="${videoDetailUrl}">🔍 Video blob</a>
                        ${thumbCid ? `<a href="#/${did}/blobs/${thumbCid}">🖼️ Thumbnail blob</a>` : ''}
                    </div>
                `;
            } else {
                videoHtml = `
                    <div class="video-placeholder">
                        <span style="font-size: 48px;">🎬</span>
                        <p>Video attached</p>
                        ${alt ? `<p class="video-alt">${escapeHtml(alt)}</p>` : ''}
                    </div>
                `;
            }
            
            return `
                <div class="embed embed-video">
                    <div class="embed-label">🎬 Video</div>
                    ${videoHtml}
                </div>
            `;
        }

        // Audio (for completeness)
        if (type === 'app.bsky.embed.audio' || embed.audio) {
            const audio = embed.audio || embed;
            const audioCid = RecordRenderers.extractBlobCid(audio);
            const audioMime = audio.mimeType || 'audio/*';
            const audioSize = audio.size;
            
            let audioHtml = '';
            if (audioCid && did) {
                const audioUrl = `/xrpc/com.atproto.sync.getBlob?did=${encodeURIComponent(did)}&cid=${encodeURIComponent(audioCid)}`;
                const audioDetailUrl = `#/${did}/blobs/${audioCid}`;
                
                audioHtml = `
                    <div class="embed-audio-player">
                        <audio src="${audioUrl}" controls preload="metadata" class="embed-audio-element">
                            Your browser doesn't support audio playback.
                        </audio>
                    </div>
                    <div class="audio-meta">
                        <span>🎵 ${audioMime}</span>
                        ${audioSize ? `<span>📦 ${RecordRenderers.formatFileSize(audioSize)}</span>` : ''}
                    </div>
                    <div class="audio-blob-link">
                        <a href="${audioDetailUrl}">🔍 View audio blob</a>
                    </div>
                `;
            } else {
                audioHtml = `
                    <div class="audio-placeholder">
                        <span style="font-size: 48px;">🎵</span>
                        <p>Audio attached</p>
                    </div>
                `;
            }
            
            return `
                <div class="embed embed-audio">
                    <div class="embed-label">🎵 Audio</div>
                    ${audioHtml}
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
