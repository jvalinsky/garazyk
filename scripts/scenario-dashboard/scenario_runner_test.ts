/**
 * Unit tests for ScenarioRunner button props derivation logic.
 *
 * Tests the pure deriveButtonProps function in isolation — no Preact,
 * no signals, no DOM required.
 */

import { assert, assertEquals } from "@std/assert";
import { deriveButtonProps } from "./islands/ScenarioRunnerHelpers.ts";
import type { ScenarioRunnerButtonProps } from "./islands/ScenarioRunnerHelpers.ts";

Deno.test("deriveButtonProps: agentMode=true, busy=false — disabled, agent label, onClickIgnored", () => {
  const props = deriveButtonProps(true, false);
  assertEquals(props, {
    disabled: true,
    label: "Disable Agent Mode to run individually",
    onClickIgnored: true,
  } satisfies ScenarioRunnerButtonProps);
});

Deno.test("deriveButtonProps: agentMode=true, busy=true — disabled, agent label, onClickIgnored", () => {
  const props = deriveButtonProps(true, true);
  assertEquals(props, {
    disabled: true,
    label: "Disable Agent Mode to run individually",
    onClickIgnored: true,
  } satisfies ScenarioRunnerButtonProps);
});

Deno.test("deriveButtonProps: agentMode=false, busy=true — disabled, busy label", () => {
  const props = deriveButtonProps(false, true);
  assertEquals(props, {
    disabled: true,
    label: "Starting Run...",
    onClickIgnored: false,
  } satisfies ScenarioRunnerButtonProps);
});

Deno.test("deriveButtonProps: agentMode=false, busy=false — enabled, run label", () => {
  const props = deriveButtonProps(false, false);
  assertEquals(props, {
    disabled: false,
    label: "Run This Scenario",
    onClickIgnored: false,
  } satisfies ScenarioRunnerButtonProps);
});

Deno.test("deriveButtonProps: onClickIgnored mirrors agentMode", () => {
  const withAgent = deriveButtonProps(true, false);
  assert(withAgent.onClickIgnored);

  const withoutAgent = deriveButtonProps(false, true);
  assert(!withoutAgent.onClickIgnored);

  const idle = deriveButtonProps(false, false);
  assert(!idle.onClickIgnored);
});

Deno.test("deriveButtonProps: disabled is true whenever busy or agentMode", () => {
  // All combos where disabled should be true
  assert(deriveButtonProps(true, false).disabled);
  assert(deriveButtonProps(true, true).disabled);
  assert(deriveButtonProps(false, true).disabled);

  // Only false when neither
  assert(!deriveButtonProps(false, false).disabled);
});
