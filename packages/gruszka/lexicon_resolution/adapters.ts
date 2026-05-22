/**
 * Sans-IO lexicon resolution — layer 3: Deno IO adapters.
 *
 * Production implementations of the {@link DnsResolver}, {@link DidResolver},
 * and {@link RecordFetcher} port interfaces using Deno's built-in
 * `Deno.resolveDns` and `fetch` APIs.
 *
 * These adapters are swappable — pass stub implementations in tests to
 * exercise the state machine without real network calls.
 *
 * @module lexicon_resolution
 */

import type { DidResolver, DnsResolver, RecordFetcher } from "./ports.ts";
import type { Did, DidDocument, Domain, LexiconDoc, Result } from "./types.ts";

// ---------------------------------------------------------------------------
// DenoDnsResolver
// ---------------------------------------------------------------------------

/**
 * DNS resolver backed by {@link https://docs.deno.com/api/deno/~/Deno.resolveDns | Deno.resolveDns}.
 *
 * Prepends the `_lexicon` subdomain prefix and queries TXT records for the
 * resulting FQDN.
 *
 * @example
 * ```ts
 * const dns = new DenoDnsResolver();
 * const result = await dns.resolveTxt(asDomain("feed.bsky.app"));
 * // result.ok === true → result.value is string[][]
 * ```
 */
export class DenoDnsResolver implements DnsResolver {
  /** Subdomain prefix for AT Protocol lexicon DNS queries. */
  private readonly prefix = "_lexicon";

  /**
   * Resolve TXT records for `_lexicon.<domain>`.
   *
   * Uses {@link Deno.resolveDns} with record type `"TXT"`. Each DNS TXT
   * record response contains an array of character-string values, which
   * this method surfaces directly as `string[][]`.
   *
   * @param domain - The DNS domain (without the `_lexicon` prefix).
   * @returns On success: the raw TXT record arrays. On failure: an error
   *          reason string.
   */
  async resolveTxt(domain: Domain): Promise<Result<string[][], string>> {
    const fqdn = `${this.prefix}.${domain}`;
    try {
      const records = await Deno.resolveDns(fqdn, "TXT");
      return { ok: true, value: records };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      return { ok: false, error: `DNS query failed for ${fqdn}: ${reason}` };
    }
  }
}

// ---------------------------------------------------------------------------
// HttpDidResolver
// ---------------------------------------------------------------------------

/**
 * DID resolver backed by the standard {@link fetch} API.
 *
 * Supports two DID methods:
 *
 * | Method     | Resolution endpoint                |
 * |------------|------------------------------------|
 * | `did:plc`  | `https://plc.directory/<did>`     |
 * | `did:web`  | `https://<domain>/.well-known/did.json` |
 *
 * @example
 * ```ts
 * const didResolver = new HttpDidResolver();
 * const result = await didResolver.resolve(asDid("did:plc:ewvi7nxzyoun6zhxrhs64oiz"));
 * // result.ok === true → result.value is DidDocument
 * ```
 */
export class HttpDidResolver implements DidResolver {
  /** Base URL of the PLC directory (DID resolution for `did:plc`). */
  private readonly plcDirectory = "https://plc.directory";

  /**
   * Resolve a DID to its DID document via HTTP.
   *
   * For `did:plc` DIDs, queries `https://plc.directory/<did>`. For `did:web`
   * DIDs, constructs the well-known URL from the domain portion of the DID
   * and fetches `https://<domain>/.well-known/did.json`.
   *
   * @param did - The DID to resolve.
   * @returns On success: the parsed DID document. On failure: an error reason
   *          string.
   */
  async resolve(did: Did): Promise<Result<DidDocument, string>> {
    try {
      const url = this.buildResolutionUrl(did);
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) {
        return {
          ok: false,
          error: `DID resolution returned HTTP ${response.status} for ${did}`,
        };
      }
      const document = await response.json() as DidDocument;
      return { ok: true, value: document };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      return {
        ok: false,
        error: `DID resolution failed for ${did}: ${reason}`,
      };
    }
  }

  /**
   * Build the resolution URL for a given DID.
   *
   * @param did - The DID to build a URL for.
   * @returns The fully qualified resolution URL.
   */
  private buildResolutionUrl(did: Did): string {
    if (did.startsWith("did:plc:")) {
      // DIDs contain only safe ASCII characters ([a-z0-9.:-]); no encoding
      // needed. encodeURIComponent would percent-encode the colons, which
      // the PLC directory does not expect.
      return `${this.plcDirectory}/${did}`;
    }
    if (did.startsWith("did:web:")) {
      // did:web:<domain>[:<path>] → https://<domain>[/<path>]/.well-known/did.json
      const identifier = did.slice("did:web:".length);
      const parts = identifier.split(":");
      const domain = parts[0] ?? identifier;
      const path = parts.slice(1).join("/");
      const base = `https://${domain}`;
      const wellKnown = path
        ? `${base}/${path}/.well-known/did.json`
        : `${base}/.well-known/did.json`;
      return wellKnown;
    }
    // Fallback: attempt PLC directory — other DID methods may be supported
    // by the directory or a future registry.
    return `${this.plcDirectory}/${did}`;
  }
}

// ---------------------------------------------------------------------------
// HttpRecordFetcher
// ---------------------------------------------------------------------------

/**
 * Lexicon record fetcher backed by the standard {@link fetch} API.
 *
 * Calls the `com.atproto.repo.getRecord` XRPC endpoint on a PDS and extracts
 * the `.value` field from the response envelope.
 *
 * @example
 * ```ts
 * const fetcher = new HttpRecordFetcher();
 * const url = buildXrpcUrl("https://pds.example", asDid("did:plc:test"), asNsid("app.bsky.feed.post"));
 * const result = await fetcher.fetch(url);
 * // result.ok === true → result.value is LexiconDoc
 * ```
 */
export class HttpRecordFetcher implements RecordFetcher {
  /**
   * Fetch a lexicon record from a PDS.
   *
   * The AT Protocol `com.atproto.repo.getRecord` endpoint wraps the record
   * in an envelope with `uri`, `cid`, and `value` fields. This method extracts
   * the `value` field and returns it as the lexicon document.
   *
   * @param endpoint - The fully constructed XRPC URL.
   * @returns On success: the lexicon document (extracted from the envelope).
   *          On failure: an error reason string.
   */
  async fetch(endpoint: string): Promise<Result<LexiconDoc, string>> {
    try {
      const response = await fetch(endpoint, {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) {
        return {
          ok: false,
          error:
            `Record fetch returned HTTP ${response.status} for ${endpoint}`,
        };
      }
      const envelope = await response.json() as { value?: LexiconDoc };
      if (!envelope.value || typeof envelope.value.lexicon !== "number") {
        return {
          ok: false,
          error:
            `Record fetch response missing or invalid .value field for ${endpoint}`,
        };
      }
      return { ok: true, value: envelope.value };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      return {
        ok: false,
        error: `Record fetch failed for ${endpoint}: ${reason}`,
      };
    }
  }
}
