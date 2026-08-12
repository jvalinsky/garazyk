/**
 * Minimal STAR-lite v0 (`application/x.microcosm.star-lite`) archive parser for
 * export benchmarks and e2e correctness checks.
 *
 * Wire layout matches ADR 0034 / Garazyk/Tests/Repository/STARLiteV0Tests.m.
 */

export const STAR_LITE_V0_MAGIC = new Uint8Array([0x2a, 0x6c, 0x00]);
export const STAR_LITE_V0_HEADER_PREFIX_BYTES = 39; // magic + 36-byte CID before commit varint

export interface StarLiteV0Record {
  key: string;
  recordBytes: Uint8Array;
}

export interface StarLiteV0Archive {
  mstRootCid: Uint8Array;
  headerBytes: number;
  records: StarLiteV0Record[];
}

export function readVarint(
  bytes: Uint8Array,
  offset: number,
): { value: bigint; nextOffset: number } | null {
  let result = 0n;
  let shift = 0n;
  let pos = offset;
  while (pos < bytes.length) {
    const byte = BigInt(bytes[pos++]);
    result |= (byte & 0x7fn) << shift;
    shift += 7n;
    if ((byte & 0x80n) === 0n) {
      return { value: result, nextOffset: pos };
    }
    if (shift > 63n) return null;
  }
  return null;
}

function assertMagic(bytes: Uint8Array): void {
  if (
    bytes.length < 3 ||
    bytes[0] !== STAR_LITE_V0_MAGIC[0] ||
    bytes[1] !== STAR_LITE_V0_MAGIC[1] ||
    bytes[2] !== STAR_LITE_V0_MAGIC[2]
  ) {
    throw new Error("invalid STAR-lite v0 magic");
  }
}

/** Parse the fixed header prefix and return the byte offset where records begin. */
export function starLiteV0HeaderEndOffset(bytes: Uint8Array): number {
  assertMagic(bytes);
  if (bytes.length < STAR_LITE_V0_HEADER_PREFIX_BYTES) {
    throw new Error("truncated STAR-lite v0 header");
  }
  const commitLen = readVarint(bytes, STAR_LITE_V0_HEADER_PREFIX_BYTES);
  if (!commitLen) throw new Error("truncated STAR-lite v0 commit length");
  const end = commitLen.nextOffset + Number(commitLen.value);
  if (end > bytes.length) throw new Error("truncated STAR-lite v0 partial commit");
  return end;
}

/** Parse a full STAR-lite v0 archive into header metadata and flat records. */
export function parseStarLiteV0(bytes: Uint8Array): StarLiteV0Archive {
  assertMagic(bytes);
  if (bytes.length < STAR_LITE_V0_HEADER_PREFIX_BYTES) {
    throw new Error("truncated STAR-lite v0 archive");
  }
  const mstRootCid = bytes.slice(3, 39);
  const headerEnd = starLiteV0HeaderEndOffset(bytes);
  const records: StarLiteV0Record[] = [];
  let offset = headerEnd;

  while (offset < bytes.length) {
    const keyLen = readVarint(bytes, offset);
    if (!keyLen) throw new Error("truncated STAR-lite v0 key length");
    offset = keyLen.nextOffset;
    const keySize = Number(keyLen.value);
    if (keySize <= 0 || offset + keySize > bytes.length) {
      throw new Error("invalid STAR-lite v0 key length");
    }
    const keyBytes = bytes.slice(offset, offset + keySize);
    offset += keySize;
    const key = new TextDecoder().decode(keyBytes);
    if (!key) throw new Error("STAR-lite v0 key must be UTF-8");

    const recLen = readVarint(bytes, offset);
    if (!recLen) throw new Error("truncated STAR-lite v0 record length");
    offset = recLen.nextOffset;
    const recordSize = Number(recLen.value);
    if (recordSize <= 0 || offset + recordSize > bytes.length) {
      throw new Error("invalid STAR-lite v0 record length");
    }
    records.push({
      key,
      recordBytes: bytes.slice(offset, offset + recordSize),
    });
    offset += recordSize;
  }

  if (offset !== bytes.length) {
    throw new Error("trailing bytes after STAR-lite v0 records");
  }

  return { mstRootCid, headerBytes: headerEnd, records };
}

/** Collect post collection keys (`app.bsky.feed.post/...`) from a parsed archive. */
export function starLitePostKeys(archive: StarLiteV0Archive): string[] {
  return archive.records
    .map((r) => r.key)
    .filter((k) => k.startsWith("app.bsky.feed.post/"))
    .sort();
}
