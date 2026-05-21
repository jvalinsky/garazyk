/**
 * Sans-IO lexicon resolution — layer 3: IO port interfaces.
 *
 * Defines the three capability interfaces the resolver state machine needs:
 * {@link DnsResolver}, {@link DidResolver}, and {@link RecordFetcher}.
 * Each interface declares exactly one async method; implementations are
 * provided by the adapters layer ({@link ./adapters.ts}) and swappable in
 * tests.
 *
 * @module lexicon_resolution
 */

import type { Did, DidDocument, Domain, LexiconDoc, Result } from "./types.ts";

// ---------------------------------------------------------------------------
// DnsResolver
// ---------------------------------------------------------------------------

/**
 * Resolve DNS TXT records for the `_lexicon.<domain>` query.
 *
 * The resolver state machine expects the adapter to prepend the `_lexicon`
 * subdomain prefix: when the command is `{ type: "resolveDns", domain:
 * "feed.bsky.app" }`, the adapter queries `_lexicon.feed.bsky.app`.
 *
 * Each entry in the returned array is one DNS TXT record; the inner array
 * contains the character-string values for that record (DNS TXT records can
 * be split across multiple character strings per RFC 1035 § 3.3.14).
 *
 * Implementations:
 * - **Deno**: {@link DenoDnsResolver} wraps `Deno.resolveDns`.
 * - **Node**: wrap `dns.promises.resolveTxt`.
 * - **Browser**: use DNS-over-HTTPS (DoH) to a public resolver.
 */
export interface DnsResolver {
  /**
   * Query TXT records for a domain.
   *
   * @param domain - The domain to query (without the `_lexicon` prefix;
   *                 the adapter is responsible for prepending it).
   * @returns On success: the raw TXT record arrays. On failure: an error
   *          reason string suitable for diagnostics.
   */
  resolveTxt(domain: Domain): Promise<Result<string[][], string>>;
}

// ---------------------------------------------------------------------------
// DidResolver
// ---------------------------------------------------------------------------

/**
 * Resolve a DID to its DID document.
 *
 * Implementations are expected to handle at least `did:plc` and `did:web`
 * methods, as these are the DID methods relevant to AT Protocol lexicon
 * resolution.
 *
 * Implementations:
 * - **Deno / browser**: {@link HttpDidResolver} uses `fetch` to a PLC
 *   directory or well-known endpoint.
 * - **Tests**: a stub that returns a pre-canned {@link DidDocument}.
 */
export interface DidResolver {
  /**
   * Resolve a DID to its DID document.
   *
   * @param did - The DID to resolve (e.g. `did:plc:ewvi7nxzyoun6zhxrhs64oiz`).
   * @returns On success: the DID document. On failure: an error reason string.
   */
  resolve(did: Did): Promise<Result<DidDocument, string>>;
}

// ---------------------------------------------------------------------------
// RecordFetcher
// ---------------------------------------------------------------------------

/**
 * Fetch a lexicon record from a PDS via the `com.atproto.repo.getRecord`
 * XRPC endpoint.
 *
 * The endpoint URL is fully constructed by the resolver's
 * {@link buildXrpcUrl} and includes the DID, collection, and record key as
 * query parameters. The adapter is responsible only for the HTTP request
 * and response parsing.
 *
 * Implementations:
 * - **Deno / browser**: {@link HttpRecordFetcher} uses `fetch`.
 * - **Tests**: a stub that returns a pre-canned {@link LexiconDoc}.
 */
export interface RecordFetcher {
  /**
   * Fetch a lexicon record from a PDS.
   *
   * @param endpoint - The fully constructed XRPC URL (from
   *                   {@link buildXrpcUrl}).
   * @returns On success: the lexicon document. On failure: an error reason
   *          string.
   */
  fetch(endpoint: string): Promise<Result<LexiconDoc, string>>;
}
