import { assertEquals, assertRejects, assertMatch, assertStringIncludes } from "@std/assert";

export const assert = {
  equal: assertEquals,
  rejects: assertRejects,
  match: assertMatch,
  includes: assertStringIncludes,
  isTrue: (expr: boolean, msg?: string) => assertEquals(expr, true, msg),
  isFalse: (expr: boolean, msg?: string) => assertEquals(expr, false, msg),
  isNotNull: (val: any, msg?: string) => {
    if (val === null || val === undefined) {
      throw new Error(msg || `Expected value to not be null/undefined, got ${val}`);
    }
  }
};
