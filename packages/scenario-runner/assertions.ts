/**
 * Test assertion helpers wrapping @std/assert.
 * @module assertions
 */
import { assertEquals, assertMatch, assertRejects, assertStringIncludes } from "@std/assert";

/**
 * Assertion object providing common test checks.
 */
export const assert = {
  /** Assert that two values are equal */
  equal: assertEquals,
  /** Assert that a function call rejects */
  rejects: assertRejects,
  /** Assert that a string matches a regex */
  match: assertMatch,
  /** Assert that a string includes a substring */
  includes: assertStringIncludes,
  /**
   * Assert that an expression is true
   * @param expr - The boolean expression to test
   * @param msg - Optional error message
   */
  isTrue: (expr: boolean, msg?: string): void => assertEquals(expr, true, msg),
  /**
   * Assert that an expression is false
   * @param expr - The boolean expression to test
   * @param msg - Optional error message
   */
  isFalse: (expr: boolean, msg?: string): void => assertEquals(expr, false, msg),
  /**
   * Assert that a value is not null or undefined
   * @param val - The value to check
   * @param msg - Optional error message
   * @throws Error if value is null or undefined
   */
  isNotNull: (val: any, msg?: string): void => {
    if (val === null || val === undefined) {
      throw new Error(msg || `Expected value to not be null/undefined, got ${val}`);
    }
  },
};
