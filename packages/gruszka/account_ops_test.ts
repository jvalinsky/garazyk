/** Tests for gruszka/account_ops.ts — pure crypto helpers. @module account_ops_test */

import { assertEquals, assertMatch } from "@std/assert";
import {
  generateInviteCode,
  generatePassword,
  randomString,
} from "./account_ops.ts";

// ---------------------------------------------------------------------------
// randomString
// ---------------------------------------------------------------------------

Deno.test("randomString: returns string of exactly the requested length", () => {
  assertEquals(randomString("abc", 10).length, 10);
  assertEquals(randomString("xyz", 1).length, 1);
  assertEquals(randomString("ab", 50).length, 50);
});

Deno.test("randomString: only uses characters from the alphabet", () => {
  const alphabet = "abcde";
  const result = randomString(alphabet, 200);
  for (const ch of result) {
    assertEquals(alphabet.includes(ch), true);
  }
});

Deno.test("randomString: single-character alphabet produces repeated character", () => {
  assertEquals(randomString("X", 5), "XXXXX");
});

Deno.test("randomString: length 0 returns empty string", () => {
  assertEquals(randomString("abc", 0), "");
});

// ---------------------------------------------------------------------------
// generateInviteCode
// ---------------------------------------------------------------------------

Deno.test("generateInviteCode: default produces 4 groups of 5 base-32 characters", () => {
  const code = generateInviteCode();
  assertMatch(code, /^[A-Z2-7]{5}-[A-Z2-7]{5}-[A-Z2-7]{5}-[A-Z2-7]{5}$/);
});

Deno.test("generateInviteCode: custom groups and length", () => {
  const code = generateInviteCode(2, 3);
  assertMatch(code, /^[A-Z2-7]{3}-[A-Z2-7]{3}$/);
});

Deno.test("generateInviteCode: total character count matches groups * groupLength", () => {
  // 3 groups of 4, plus 2 hyphens = 14 chars total
  const code = generateInviteCode(3, 4);
  assertEquals(code.length, 3 * 4 + 2);
});

Deno.test("generateInviteCode: each call produces a different code (probabilistic)", () => {
  const codes = new Set<string>();
  for (let i = 0; i < 20; i++) codes.add(generateInviteCode());
  // With 32^20 space, 20 calls should never collide
  assertEquals(codes.size, 20);
});

// ---------------------------------------------------------------------------
// generatePassword
// ---------------------------------------------------------------------------

Deno.test("generatePassword: default length is 24", () => {
  assertEquals(generatePassword().length, 24);
});

Deno.test("generatePassword: custom length is respected", () => {
  assertEquals(generatePassword(48).length, 48);
  assertEquals(generatePassword(1).length, 1);
});

Deno.test("generatePassword: only uses alphanumeric characters", () => {
  const pw = generatePassword(200);
  assertMatch(pw, /^[a-zA-Z0-9]+$/);
});
