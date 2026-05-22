/**
 * Lexicon resolution — cache layer.
 *
 * Provides {@link KeyValueCache}, {@link InMemoryCache}, and {@link DiskCache}
 * implementations for wrapping the IO port interfaces
 * ({@link DnsResolver}, {@link DidResolver}, {@link RecordFetcher}) with
 * transparent caching.
 *
 * Caching is layered outside the sans-IO state machine — the state machine
 * never knows about the cache; it just calls the port interfaces as usual.
 *
 * @module lexicon_resolution
 */

import type { Did, DidDocument, Domain, LexiconDoc, Result } from "./types.ts";
import type { DidResolver, DnsResolver, RecordFetcher } from "./ports.ts";

// ---------------------------------------------------------------------------
// Cache entry
// ---------------------------------------------------------------------------

/**
 * A single cache entry with an expiration timestamp.
 *
 * @typeParam T - The type of the cached value.
 */
interface CacheEntry<T> {
  /** The cached value. */
  value: T;
  /** Unix timestamp in milliseconds after which this entry is stale. */
  expiresAt: number;
}

// ---------------------------------------------------------------------------
// KeyValueCache interface
// ---------------------------------------------------------------------------

/**
 * Generic key-value cache with TTL support.
 *
 * Implementations include {@link InMemoryCache} (fast, ephemeral) and
 * {@link DiskCache} (persistent across restarts).
 *
 * @typeParam T - The type of cached values.
 */
export interface KeyValueCache<T> {
  /**
   * Retrieve a cached value, or `undefined` if absent or expired.
   *
   * @param key - The cache key.
   * @returns The cached value, or `undefined`.
   */
  get(key: string): Promise<T | undefined>;

  /**
   * Store a value in the cache with an optional TTL.
   *
   * @param key - The cache key.
   * @param value - The value to cache.
   * @param ttlMs - Time-to-live in milliseconds. Defaults to implementation
   *                default (typically 24 hours for DiskCache, no limit for
   *                InMemoryCache if not specified).
   */
  set(key: string, value: T, ttlMs?: number): Promise<void>;

  /**
   * Remove all expired entries.
   *
   * Called opportunistically — implementations may also clean up lazily.
   */
  evictExpired(): Promise<void>;

  /**
   * Remove all entries from the cache.
   */
  clear(): Promise<void>;
}

// ---------------------------------------------------------------------------
// InMemoryCache
// ---------------------------------------------------------------------------

/**
 * In-memory key-value cache backed by a {@link Map}.
 *
 * Fastest option — all entries live in process memory.  Best for short-lived
 * processes or when cache persistence is not needed.
 *
 * @typeParam T - The type of cached values.
 *
 * @example
 * ```ts
 * const cache = new InMemoryCache<LexiconDoc>({ ttlMs: 60 * 60 * 1000 }); // 1 hour
 * await cache.set("app.bsky.feed.post", lexiconDoc);
 * const doc = await cache.get("app.bsky.feed.post");
 * ```
 */
export class InMemoryCache<T> implements KeyValueCache<T> {
  /** Default TTL in milliseconds (no expiry if not set). */
  private readonly defaultTtlMs: number | undefined;

  /** Internal storage. */
  private readonly store = new Map<string, CacheEntry<T>>();

  /**
   * @param opts - Configuration options.
   * @param opts.ttlMs - Default TTL for entries set without an explicit TTL.
   *                     If omitted, entries never expire by default.
   */
  constructor(opts: { ttlMs?: number } = {}) {
    this.defaultTtlMs = opts.ttlMs;
  }

  /** @inheritdoc */
  async get(key: string): Promise<T | undefined> {
    const entry = this.store.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt < Date.now()) {
      this.store.delete(key);
      return undefined;
    }
    return entry.value;
  }

  /** @inheritdoc */
  async set(key: string, value: T, ttlMs?: number): Promise<void> {
    const effectiveTtl = ttlMs ?? this.defaultTtlMs;
    const expiresAt = effectiveTtl != null
      ? Date.now() + effectiveTtl
      : Number.POSITIVE_INFINITY;
    this.store.set(key, { value, expiresAt });
  }

  /** @inheritdoc */
  async evictExpired(): Promise<void> {
    const now = Date.now();
    for (const [key, entry] of this.store) {
      if (entry.expiresAt < now) {
        this.store.delete(key);
      }
    }
  }

  /** @inheritdoc */
  async clear(): Promise<void> {
    this.store.clear();
  }

  /** Number of entries currently in the store (including expired). */
  get size(): number {
    return this.store.size;
  }
}

// ---------------------------------------------------------------------------
// Hash helper for DiskCache filenames
// ---------------------------------------------------------------------------

/**
 * djb2 string hash (non-cryptographic).
 *
 * Produces a 32-bit unsigned integer hash from a string, suitable for
 * generating collision-resistant filenames from arbitrary cache keys.
 */
function hashDjb2(s: string): number {
  let hash = 5381;
  for (let i = 0; i < s.length; i++) {
    hash = ((hash << 5) + hash + s.charCodeAt(i)) | 0;
  }
  return hash >>> 0;
}

// ---------------------------------------------------------------------------
// DiskCache
// ---------------------------------------------------------------------------

/**
 * Persistent file-system key-value cache.
 *
 * Each entry is stored as a separate JSON file in a configurable directory.
 * Expired entries are removed lazily on read and eagerly via
 * {@link evictExpired}.
 *
 * Requires `--allow-read` and `--allow-write` Deno permissions for the
 * cache directory.
 *
 * @typeParam T - The type of cached values (must be JSON-serializable).
 *
 * @example
 * ```ts
 * const cache = new DiskCache<LexiconDoc>({
 *   directory: "/tmp/lexicon-cache",
 *   ttlMs: 24 * 60 * 60 * 1000, // 24 hours
 * });
 * ```
 */
export class DiskCache<T> implements KeyValueCache<T> {
  /** Default TTL in milliseconds. */
  private readonly defaultTtlMs: number;

  /** Directory path for cache files. */
  private readonly directory: string;

  /**
   * @param opts - Configuration options.
   * @param opts.directory - Directory to store cache files in.
   * @param opts.ttlMs - Default TTL for entries set without an explicit TTL.
   *                     Defaults to 24 hours.
   */
  constructor(opts: { directory: string; ttlMs?: number }) {
    this.directory = opts.directory;
    this.defaultTtlMs = opts.ttlMs ?? 24 * 60 * 60 * 1000;
  }

  /** @inheritdoc */
  async get(key: string): Promise<T | undefined> {
    const path = this.keyPath(key);
    try {
      const raw = await Deno.readTextFile(path);
      const entry = JSON.parse(raw) as CacheEntry<T> & { value: unknown };
      if (entry.expiresAt < Date.now()) {
        // Lazy eviction — remove the stale file.
        await this.removeFile(path);
        return undefined;
      }
      return entry.value as T;
    } catch (err) {
      if (err instanceof Deno.errors.NotFound) return undefined;
      // Corrupt file or permission error — treat as miss.
      return undefined;
    }
  }

  /** @inheritdoc */
  async set(key: string, value: T, ttlMs?: number): Promise<void> {
    const effectiveTtl = ttlMs ?? this.defaultTtlMs;
    const entry: CacheEntry<T> = {
      value,
      expiresAt: Date.now() + effectiveTtl,
    };
    const path = this.keyPath(key);
    await this.ensureDirectory();
    await Deno.writeTextFile(path, JSON.stringify(entry));
  }

  /** @inheritdoc */
  async evictExpired(): Promise<void> {
    await this.ensureDirectory();
    const now = Date.now();
    for await (const entry of Deno.readDir(this.directory)) {
      if (!entry.isFile) continue;
      const path = `${this.directory}/${entry.name}`;
      try {
        const raw = await Deno.readTextFile(path);
        const cached = JSON.parse(raw) as CacheEntry<unknown>;
        if (cached.expiresAt < now) {
          await this.removeFile(path);
        }
      } catch {
        // Corrupt or unreadable — remove it.
        await this.removeFile(path);
      }
    }
  }

  /** @inheritdoc */
  async clear(): Promise<void> {
    try {
      await Deno.remove(this.directory, { recursive: true });
    } catch (err) {
      if (!(err instanceof Deno.errors.NotFound)) throw err;
    }
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  /** Convert a cache key to a safe filename using a djb2 hash. */
  private keyPath(key: string): string {
    const hash = hashDjb2(key);
    return `${this.directory}/${hash}.json`;
  }

  /** Ensure the cache directory exists. */
  private async ensureDirectory(): Promise<void> {
    try {
      await Deno.mkdir(this.directory, { recursive: true });
    } catch (err) {
      if (!(err instanceof Deno.errors.AlreadyExists)) throw err;
    }
  }

  /** Attempt to remove a file, ignoring NotFound. */
  private async removeFile(path: string): Promise<void> {
    try {
      await Deno.remove(path);
    } catch (err) {
      if (!(err instanceof Deno.errors.NotFound)) throw err;
    }
  }
}

// ---------------------------------------------------------------------------
// CachingRecordFetcher
// ---------------------------------------------------------------------------

/**
 * A {@link RecordFetcher} that wraps another fetcher with a cache.
 *
 * Cache hits return immediately; cache misses delegate to the inner fetcher
 * and populate the cache on success. Errors are not cached — the next
 * request for the same key will retry the inner fetcher.
 *
 * @example
 * ```ts
 * const inner = new HttpRecordFetcher();
 * const cache = new InMemoryCache<LexiconDoc>({ ttlMs: 24 * 60 * 60 * 1000 });
 * const cached = new CachingRecordFetcher(inner, cache);
 * ```
 */
export class CachingRecordFetcher implements RecordFetcher {
  /**
   * @param inner - The underlying record fetcher.
   * @param cache - The cache to use for storing/retrieving lexicon documents.
   */
  constructor(
    private readonly inner: RecordFetcher,
    private readonly cache: KeyValueCache<LexiconDoc>,
  ) {}

  /** @inheritdoc */
  async fetch(endpoint: string): Promise<Result<LexiconDoc, string>> {
    // Check cache first.
    const cached = await this.cache.get(endpoint);
    if (cached !== undefined) {
      return { ok: true, value: cached };
    }

    // Miss — delegate to inner fetcher.
    const result = await this.inner.fetch(endpoint);
    if (result.ok) {
      await this.cache.set(endpoint, result.value);
    }
    // Errors are not cached.
    return result;
  }
}

// ---------------------------------------------------------------------------
// CachingDnsResolver
// ---------------------------------------------------------------------------

/**
 * A {@link DnsResolver} that wraps another resolver with a cache.
 *
 * Cache hits return immediately; cache misses delegate to the inner resolver
 * and populate the cache on success. Errors are not cached.
 */
export class CachingDnsResolver implements DnsResolver {
  /**
   * @param inner - The underlying DNS resolver.
   * @param cache - The cache to use for storing/retrieving DNS TXT records.
   */
  constructor(
    private readonly inner: DnsResolver,
    private readonly cache: KeyValueCache<string[][]>,
  ) {}

  /** @inheritdoc */
  async resolveTxt(domain: Domain): Promise<Result<string[][], string>> {
    const cached = await this.cache.get(domain);
    if (cached !== undefined) {
      return { ok: true, value: cached };
    }

    const result = await this.inner.resolveTxt(domain);
    if (result.ok) {
      await this.cache.set(domain, result.value);
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// CachingDidResolver
// ---------------------------------------------------------------------------

/**
 * A {@link DidResolver} that wraps another resolver with a cache.
 *
 * Cache hits return immediately; cache misses delegate to the inner resolver
 * and populate the cache on success. Errors are not cached.
 */
export class CachingDidResolver implements DidResolver {
  /**
   * @param inner - The underlying DID resolver.
   * @param cache - The cache to use for storing/retrieving DID documents.
   */
  constructor(
    private readonly inner: DidResolver,
    private readonly cache: KeyValueCache<DidDocument>,
  ) {}

  /** @inheritdoc */
  async resolve(did: Did): Promise<Result<DidDocument, string>> {
    const cached = await this.cache.get(did);
    if (cached !== undefined) {
      return { ok: true, value: cached };
    }

    const result = await this.inner.resolve(did);
    if (result.ok) {
      await this.cache.set(did, result.value);
    }
    return result;
  }
}
