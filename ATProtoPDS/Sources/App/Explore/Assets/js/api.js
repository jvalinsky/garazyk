const API_BASE = '/explore/api';

// Client-side cache with TTL
const clientCache = new Map();
const CACHE_TTL = {
    did: 5 * 60 * 1000,       // 5 minutes (shorter than server cache)
    plc: 10 * 60 * 1000,      // 10 minutes
    describe: 2 * 60 * 1000,  // 2 minutes
    records: 2 * 60 * 1000,   // 2 minutes
    record: 5 * 60 * 1000     // 5 minutes
};

function getCachedOrFetch(cacheKey, ttl, fetcher) {
    const cached = clientCache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < ttl) {
        return Promise.resolve(cached.data);
    }
    return fetcher().then(data => {
        clientCache.set(cacheKey, { data, timestamp: Date.now() });
        return data;
    });
}

export const API = {
    async lookup(didOrHandle) {
        const params = new URLSearchParams();
        if (didOrHandle.startsWith('did:')) {
            params.set('did', didOrHandle);
        } else if (didOrHandle.includes('.')) {
            params.set('handle', didOrHandle);
        } else {
            return { error: 'Invalid DID or handle format' };
        }
        try {
            const response = await fetch(`${API_BASE}/lookup?${params}`);
            return await response.json();
        } catch (e) {
            return { error: e.message };
        }
    },
    
    async getDidDocument(did) {
        return getCachedOrFetch(`did:${did}`, CACHE_TTL.did, async () => {
            try {
                const params = new URLSearchParams({ did });
                const response = await fetch(`${API_BASE}/did?${params}`);
                if (!response.ok) {
                    return { error: `HTTP ${response.status}` };
                }
                return await response.json();
            } catch (e) {
                return { error: e.message };
            }
        });
    },
    
    async getPlcLog(did) {
        return getCachedOrFetch(`plc:${did}`, CACHE_TTL.plc, async () => {
            try {
                const params = new URLSearchParams({ did });
                const response = await fetch(`${API_BASE}/plc-log?${params}`);
                if (!response.ok) {
                    return { error: `HTTP ${response.status}` };
                }
                return await response.json();
            } catch (e) {
                return { error: e.message };
            }
        });
    },
    
    async getAccounts() {
        try {
            const response = await fetch(`${API_BASE}/accounts`);
            if (!response.ok) {
                return { accounts: [] };
            }
            return await response.json();
        } catch (e) {
            return { accounts: [] };
        }
    },
    
    async getRepoDescribe(did) {
        return getCachedOrFetch(`describe:${did}`, CACHE_TTL.describe, async () => {
            try {
                const params = new URLSearchParams();
                if (did) params.set('did', did);
                const response = await fetch(`${API_BASE}/describe?${params}`);
                if (!response.ok) {
                    return { error: `HTTP ${response.status}` };
                }
                return await response.json();
            } catch (e) {
                return { error: e.message };
            }
        });
    },
    
    async listRecords(did, collection, options = {}) {
        const cacheKey = `records:${did}:${collection}:${options.limit || 20}:${options.cursor || ''}`;
        return getCachedOrFetch(cacheKey, CACHE_TTL.records, async () => {
            try {
                const params = new URLSearchParams({ did, collection });
                if (options.limit) params.set('limit', String(options.limit));
                if (options.cursor) params.set('cursor', options.cursor);
                const response = await fetch(`${API_BASE}/records?${params}`);
                if (!response.ok) {
                    return { records: [], cursor: null };
                }
                return await response.json();
            } catch (e) {
                return { records: [], cursor: null };
            }
        });
    },
    
    async getRecord(uri) {
        return getCachedOrFetch(`record:${uri}`, CACHE_TTL.record, async () => {
            try {
                const params = new URLSearchParams({ uri });
                const response = await fetch(`${API_BASE}/record?${params}`);
                if (!response.ok) {
                    return { error: `HTTP ${response.status}` };
                }
                return await response.json();
            } catch (e) {
                return { error: e.message };
            }
        });
    },
    
    async getBlob(cid) {
        try {
            const params = new URLSearchParams({ cid });
            const response = await fetch(`${API_BASE}/blob?${params}`);
            if (!response.ok) {
                return null;
            }
            const contentType = response.headers.get('content-type') || 'application/octet-stream';
            const blob = await response.blob();
            return { blob, contentType };
        } catch (e) {
            return null;
        }
    },
    
    async decodeCid(cid) {
        try {
            const params = new URLSearchParams({ cid });
            const response = await fetch(`${API_BASE}/cid-decode?${params}`);
            if (!response.ok) {
                return { error: `HTTP ${response.status}` };
            }
            return await response.json();
        } catch (e) {
            return { error: e.message };
        }
    },

    async getFeedPosts(did, options = {}) {
        const cacheKey = `feed-posts:${did}:${options.limit || 20}:${options.cursor || ''}`;
        return getCachedOrFetch(cacheKey, CACHE_TTL.records || 120000, async () => {
            try {
                const params = new URLSearchParams({ did });
                if (options.limit) params.set('limit', String(options.limit));
                if (options.cursor) params.set('cursor', options.cursor);
                const response = await fetch(`${API_BASE}/feed-posts?${params}`);
                if (!response.ok) {
                    return { posts: [], cursor: null };
                }
                return await response.json();
            } catch (e) {
                return { posts: [], cursor: null };
            }
        });
    },

    async getFeedLikes(did, options = {}) {
        const cacheKey = `feed-likes:${did}:${options.limit || 20}:${options.cursor || ''}`;
        return getCachedOrFetch(cacheKey, CACHE_TTL.records || 120000, async () => {
            try {
                const params = new URLSearchParams({ did });
                if (options.limit) params.set('limit', String(options.limit));
                if (options.cursor) params.set('cursor', options.cursor);
                const response = await fetch(`${API_BASE}/feed-likes?${params}`);
                if (!response.ok) {
                    return { likes: [], cursor: null };
                }
                return await response.json();
            } catch (e) {
                return { likes: [], cursor: null };
            }
        });
    },

    async getFeedReposts(did, options = {}) {
        const cacheKey = `feed-reposts:${did}:${options.limit || 20}:${options.cursor || ''}`;
        return getCachedOrFetch(cacheKey, CACHE_TTL.records || 120000, async () => {
            try {
                const params = new URLSearchParams({ did });
                if (options.limit) params.set('limit', String(options.limit));
                if (options.cursor) params.set('cursor', options.cursor);
                const response = await fetch(`${API_BASE}/feed-reposts?${params}`);
                if (!response.ok) {
                    return { reposts: [], cursor: null };
                }
                return await response.json();
            } catch (e) {
                return { reposts: [], cursor: null };
            }
        });
    },

    async getFollows(did, options = {}) {
        const cacheKey = `graph-follows:${did}:${options.limit || 50}`;
        return getCachedOrFetch(cacheKey, CACHE_TTL.records || 120000, async () => {
            try {
                const params = new URLSearchParams({ did });
                if (options.limit) params.set('limit', String(options.limit));
                if (options.direction) params.set('direction', options.direction);
                const response = await fetch(`${API_BASE}/graph-follows?${params}`);
                if (!response.ok) {
                    return { actors: [] };
                }
                return await response.json();
            } catch (e) {
                return { actors: [] };
            }
        });
    },

    async getActorProfile(did) {
        const cacheKey = `actor-profile:${did}`;
        return getCachedOrFetch(cacheKey, CACHE_TTL.describe || 120000, async () => {
            try {
                const params = new URLSearchParams({ did });
                const response = await fetch(`${API_BASE}/actor-profile?${params}`);
                if (!response.ok) {
                    return { error: `HTTP ${response.status}` };
                }
                return await response.json();
            } catch (e) {
                return { error: e.message };
            }
        });
    }
};
