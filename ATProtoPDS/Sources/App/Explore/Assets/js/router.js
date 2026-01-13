// Hash-based router for deep linking
// URL format:
//   #/                              - Home (no account)
//   #/{did}                         - Account DID doc
//   #/{did}/plc-ops                 - PLC operations
//   #/{did}/collections             - Collections list
//   #/{did}/{collection}            - Records in collection
//   #/{did}/{collection}/{rkey}     - Specific record
//   #/cid-decode                    - CID decoder tool
//   #/cid-decode/{cid}              - CID decoder with pre-filled CID

export class Router {
    constructor() {
        this.listeners = [];
        this.currentRoute = null;
        
        // Listen for hash changes
        window.addEventListener('hashchange', () => this.handleRoute());
        window.addEventListener('popstate', () => this.handleRoute());
    }

    // Parse the current hash into route components
    parseHash() {
        const hash = window.location.hash.slice(1); // Remove #
        if (!hash || hash === '/') {
            return { type: 'home' };
        }

        const parts = hash.split('/').filter(p => p.length > 0);
        
        if (parts.length === 0) {
            return { type: 'home' };
        }

        // CID decoder tool
        if (parts[0] === 'cid-decode') {
            return {
                type: 'cid-decode',
                cid: parts[1] || null
            };
        }

        // Must start with a DID
        const did = parts[0];
        if (!did.startsWith('did:')) {
            // Could be a handle - let caller resolve it
            return { type: 'lookup', handle: did };
        }

        if (parts.length === 1) {
            // Just DID - default to did-doc
            return { type: 'did-doc', did };
        }

        const section = parts[1];

        // Known sections
        if (section === 'plc-ops') {
            return { type: 'plc-ops', did };
        }
        if (section === 'collections') {
            return { type: 'collections', did };
        }
        if (section === 'did-doc') {
            return { type: 'did-doc', did };
        }

        // Otherwise it's a collection NSID
        const collection = section;
        
        if (parts.length === 2) {
            // Collection records list
            return { type: 'records', did, collection };
        }

        // Record detail - rkey is the rest joined (in case it has slashes)
        const rkey = parts.slice(2).join('/');
        return { type: 'record', did, collection, rkey };
    }

    // Navigate to a route (updates URL and triggers handlers)
    navigate(route, replace = false) {
        const hash = this.routeToHash(route);
        
        if (replace) {
            window.history.replaceState(null, '', hash);
        } else {
            window.history.pushState(null, '', hash);
        }
        
        this.handleRoute();
    }

    // Convert route object to hash string
    routeToHash(route) {
        switch (route.type) {
            case 'home':
                return '#/';
            case 'cid-decode':
                return route.cid ? `#/cid-decode/${route.cid}` : '#/cid-decode';
            case 'did-doc':
                return `#/${route.did}`;
            case 'plc-ops':
                return `#/${route.did}/plc-ops`;
            case 'collections':
                return `#/${route.did}/collections`;
            case 'records':
                return `#/${route.did}/${route.collection}`;
            case 'record':
                return `#/${route.did}/${route.collection}/${route.rkey}`;
            default:
                return '#/';
        }
    }

    // Build an AT URI from route components
    static buildAtUri(did, collection, rkey) {
        return `at://${did}/${collection}/${rkey}`;
    }

    // Parse an AT URI into components
    static parseAtUri(uri) {
        const match = uri.match(/^at:\/\/([^\/]+)\/([^\/]+)\/(.+)$/);
        if (!match) return null;
        return {
            did: match[1],
            collection: match[2],
            rkey: match[3]
        };
    }

    // Handle the current route
    handleRoute() {
        const route = this.parseHash();
        
        // Don't re-handle the same route
        if (JSON.stringify(route) === JSON.stringify(this.currentRoute)) {
            return;
        }
        
        this.currentRoute = route;
        
        // Notify all listeners
        for (const listener of this.listeners) {
            listener(route);
        }
    }

    // Register a route change listener
    onRouteChange(callback) {
        this.listeners.push(callback);
    }

    // Initialize and handle initial route
    init() {
        this.handleRoute();
    }

    // Helper to navigate to account
    goToAccount(did, section = 'did-doc') {
        this.navigate({ type: section, did });
    }

    // Helper to navigate to collection
    goToCollection(did, collection) {
        this.navigate({ type: 'records', did, collection });
    }

    // Helper to navigate to record
    goToRecord(did, collection, rkey) {
        this.navigate({ type: 'record', did, collection, rkey });
    }

    // Helper to navigate to record by AT URI
    goToRecordByUri(uri) {
        const parsed = Router.parseAtUri(uri);
        if (parsed) {
            this.goToRecord(parsed.did, parsed.collection, parsed.rkey);
        }
    }

    // Get current route
    getRoute() {
        return this.currentRoute || this.parseHash();
    }
}

// Singleton instance
export const router = new Router();
