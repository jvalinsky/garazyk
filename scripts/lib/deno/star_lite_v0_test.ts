import { assertEquals, assertThrows } from "@std/assert";
import { decode, encode } from "cborg";
import {
  parseStarLiteV0,
  readVarint,
  starLitePostKeys,
  starLiteV0HeaderEndOffset,
} from "./star_lite_v0.ts";

Deno.test("readVarint decodes single-byte values", () => {
  const bytes = new Uint8Array([0x05]);
  assertEquals(readVarint(bytes, 0), { value: 5n, nextOffset: 1 });
});

Deno.test("parseStarLiteV0 reads header-only empty archive", () => {
  const commit = encode({
    did: "did:plc:empty",
    version: 3,
    rev: "3jzempty",
    sig: new Uint8Array(64),
  });
  const commitLen = encodeVarint(commit.length);
  const cid = new Uint8Array(36);
  cid[0] = 0x01;
  cid[1] = 0x71;
  cid[2] = 0x12;
  cid[3] = 0x20;
  const bytes = concat(
    new Uint8Array([0x2a, 0x6c, 0x00]),
    cid,
    commitLen,
    commit,
  );
  const archive = parseStarLiteV0(bytes);
  assertEquals(archive.records.length, 0);
  assertEquals(starLitePostKeys(archive), []);
  assertEquals(starLiteV0HeaderEndOffset(bytes), bytes.length);
});

Deno.test("parseStarLiteV0 reads flat key-record pairs", () => {
  const commit = encode({
    did: "did:plc:fixture",
    version: 3,
    rev: "3jzfixture",
    sig: new Uint8Array(64),
  });
  const key = "app.bsky.feed.post/3jzfixture";
  const record = encode({
    $type: "app.bsky.feed.post",
    text: "hello star-lite",
    createdAt: "2026-08-12T00:00:00.000Z",
  });
  const bytes = concat(
    new Uint8Array([0x2a, 0x6c, 0x00]),
    new Uint8Array(36),
    encodeVarint(commit.length),
    commit,
    encodeVarint(key.length),
    new TextEncoder().encode(key),
    encodeVarint(record.length),
    record,
  );
  const archive = parseStarLiteV0(bytes);
  assertEquals(starLitePostKeys(archive), [key]);
  const decoded = decode(archive.records[0].recordBytes) as { text?: string };
  assertEquals(decoded.text, "hello star-lite");
});

function encodeVarint(n: number): Uint8Array {
  const out: number[] = [];
  let value = n;
  do {
    let byte = value & 0x7f;
    value >>>= 7;
    if (value > 0) byte |= 0x80;
    out.push(byte);
  } while (value > 0);
  return new Uint8Array(out);
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

Deno.test("parseStarLiteV0 rejects invalid magic", () => {
  assertThrows(() => parseStarLiteV0(new Uint8Array([0x00, 0x00, 0x00])), Error);
});
