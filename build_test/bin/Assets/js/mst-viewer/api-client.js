// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * MST Viewer API Client
 * Handles all communication with the backend MST Viewer API
 * Includes client-side caching with TTL
 */

const API_BASE = "/api/mst";

// Client-side cache with TTL
const clientCache = new Map();
const CACHE_TTL = {
  accounts: 2 * 60 * 1000, // 2 minutes
  tree: 60 * 1000, // 60 seconds
  stats: 60 * 1000, // 60 seconds
};

/**
 * Get cached data or fetch fresh data
 * @param {string} cacheKey - Unique cache key
 * @param {number} ttl - Time to live in milliseconds
 * @param {Function} fetcher - Function that returns a Promise
 * @returns {Promise} The cached or freshly fetched data
 */
function getCachedOrFetch(cacheKey, ttl, fetcher) {
  const cached = clientCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < ttl) {
    return Promise.resolve(cached.data);
  }
  return fetcher().then((data) => {
    clientCache.set(cacheKey, { data, timestamp: Date.now() });
    return data;
  });
}

/**
 * Clear a specific cache entry
 * @param {string} cacheKey - Cache key to clear
 */
function clearCache(cacheKey) {
  clientCache.delete(cacheKey);
}

/**
 * Clear all cache entries
 */
function clearAllCache() {
  clientCache.clear();
}

export const APIClient = {
  /**
   * Fetch list of all accounts
   * @returns {Promise<{accounts: Array}>} Array of accounts with DID and handle
   */
  async getAccounts() {
    return getCachedOrFetch("accounts", CACHE_TTL.accounts, async () => {
      try {
        const response = await fetch(`${API_BASE}/accounts`);
        if (!response.ok) {
          return { accounts: [], error: `HTTP ${response.status}` };
        }
        return await response.json();
      } catch (e) {
        return { accounts: [], error: e.message };
      }
    });
  },

  /**
   * Fetch MST tree structure for a given DID
   * @param {string} did - The DID to fetch the tree for
   * @returns {Promise<{root: Object}>} Tree structure in JSON format
   */
  async getTree(did) {
    if (!did) {
      return { error: "DID is required" };
    }
    return getCachedOrFetch(`tree:${did}`, CACHE_TTL.tree, async () => {
      try {
        const response = await fetch(`${API_BASE}/tree/${encodeURIComponent(did)}`);
        if (!response.ok) {
          return { error: `HTTP ${response.status}`, did };
        }
        return await response.json();
      } catch (e) {
        return { error: e.message, did };
      }
    });
  },

  /**
   * Fetch statistics for a given DID's MST
   * @param {string} did - The DID to fetch stats for
   * @returns {Promise<Object>} Statistics object
   */
  async getStats(did) {
    if (!did) {
      return { error: "DID is required" };
    }
    return getCachedOrFetch(`stats:${did}`, CACHE_TTL.stats, async () => {
      try {
        const response = await fetch(`${API_BASE}/stats/${encodeURIComponent(did)}`);
        if (!response.ok) {
          return { error: `HTTP ${response.status}`, did };
        }
        return await response.json();
      } catch (e) {
        return { error: e.message, did };
      }
    });
  },

  /**
   * Export MST in various formats
   * @param {string} did - The DID to export
   * @param {string} format - Export format: 'json', 'dot', or 'svg'
   * @returns {Promise<Response>} The export response
   */
  async exportMST(did, format = "json") {
    if (!did) {
      throw new Error("DID is required");
    }
    const validFormats = ["json", "dot", "svg"];
    if (!validFormats.includes(format)) {
      throw new Error(`Invalid format: ${format}`);
    }

    try {
      const params = new URLSearchParams({ format });
      const response = await fetch(
        `${API_BASE}/export/${encodeURIComponent(did)}?${params}`,
      );
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return response;
    } catch (e) {
      throw new Error(`Export failed: ${e.message}`);
    }
  },

  /**
   * Download exported file
   * @param {string} did - The DID to export
   * @param {string} format - Export format: 'json', 'dot', or 'svg'
   * @param {string} filename - Optional filename for the download
   */
  async downloadExport(did, format = "json", filename = null) {
    try {
      const response = await this.exportMST(did, format);
      const blob = await response.blob();

      // Generate filename if not provided
      if (!filename) {
        const shortDid = did.substring(0, Math.min(16, did.length));
        const extension = format === "svg" ? "dot" : format;
        filename = `mst-${shortDid}.${extension}`;
      }

      // Create download link
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
    } catch (e) {
      throw new Error(`Download failed: ${e.message}`);
    }
  },

  /**
   * Clear cache for a specific DID
   * @param {string} did - The DID to clear cache for
   */
  clearDIDCache(did) {
    clearCache(`tree:${did}`);
    clearCache(`stats:${did}`);
  },

  /**
   * Clear all API cache
   */
  clearAllCache() {
    clearAllCache();
  },
};

export default APIClient;
