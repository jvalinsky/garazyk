const API_BASE = '/explore/api';

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
    },
    
    async getPlcLog(did) {
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
    },
    
    async listRecords(collection, options = {}) {
        try {
            const params = new URLSearchParams({ collection });
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
    },
    
    async getRecord(uri) {
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
    }
};
