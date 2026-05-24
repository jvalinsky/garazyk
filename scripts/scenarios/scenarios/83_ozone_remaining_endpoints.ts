/**
 * @module scenarios/83_ozone_remaining_endpoints
 *
 * Scenario: Tests remaining tools.ozone.* endpoint namespaces not covered by 71.
 *
 * Behavior:
 * - Creates accounts and obtains admin token.
 * - Tests tools.ozone.set.* (sets CRUD: upsertSet, addValues, getValues, querySets, deleteValues, deleteSet).
 * - Tests tools.ozone.team.* (team member management: addMember, listMembers, updateMember, deleteMember).
 * - Tests tools.ozone.setting.* (option management: upsertOption, listOptions, removeOptions).
 * - Tests tools.ozone.communication.* (template management: createTemplate, listTemplates, updateTemplate, deleteTemplate).
 *
 * Expectations:
 * - Ozone admin endpoints return structured responses with admin auth.
 * - Unavailable endpoints are gracefully skipped (404/501).
 */

import { DEFAULT_ADMIN_PASSWORD, getActor, PDS1 } from "../../lib/deno/config.ts";
import { now, tryEndpoint, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: tools.ozone.set.{addValues,deleteSet,deleteValues,getValues,querySets,upsertSet},
//   tools.ozone.team.{addMember,deleteMember,listMembers,updateMember},
//   tools.ozone.setting.{listOptions,removeOptions,upsertOption},
//   tools.ozone.communication.{createTemplate,deleteTemplate,listTemplates,updateTemplate}.
// Extends coverage from 71_ozone_moderation_endpoints.ts to cover the remaining ozone
// namespaces. Runs against the PDS admin endpoints with admin authentication.




export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Ozone Remaining Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getActor("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Create user account ---
  const lunaSession = await timedCall(
    result,
    "Create luna account",
    async () => {
      try {
        return await pds.accounts.createAccount(luna.handle, luna.email, luna.password);
      } catch {
        return await pds.accounts.createSession(luna.handle, luna.password);
      }
    },
    (s) => `did=${s.did}`,
  );
  if (lunaSession) {
    luna.did = lunaSession.did;
    luna.accessJwt = lunaSession.accessJwt;
  }

  if (!luna.did) {
    result.stepFailed("Account setup", "missing DID");
    result.finish();
    return result;
  }

  // --- Obtain admin token ---
  const adminPassword = Deno.env.get("PDS_ADMIN_PASSWORD") ?? DEFAULT_ADMIN_PASSWORD;
  const adminToken = await timedCall(
    result,
    "Admin login",
    async () => pds.adminLogin(adminPassword),
    () => "obtained admin bearer",
  );

  if (!adminToken) {
    result.stepSkipped("All ozone endpoints", "no admin token available");
    result.finish();
    return result;
  }

  // ── 1. tools.ozone.set.* ──────────────────────────────────────────────
  // A mutable set is a named collection of values (typically DID strings).

  let setName = "test-scenario-set";

  // 1a. tools.ozone.set.upsertSet — create a new set
  await tryEndpoint(
    result,
    "ozone.set.upsertSet (create)",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.set.upsertSet", {
        name: setName,
        description: "Set created during ozone scenario coverage test",
      });
      setName = body.name ?? setName;
      return { name: body.name, description: body.description };
    },
    (r) => `name=${r.name}`,
  );

  // 1b. tools.ozone.set.addValues — add values to the set
  const testValues = [luna.did!, `did:plc:testvalue1`, `did:plc:testvalue2`];
  await tryEndpoint(
    result,
    "ozone.set.addValues",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.set.addValues", {
        name: setName,
        values: testValues,
      });
      return { count: body.set?.values?.length ?? "present" };
    },
    (r) => `values=${r.count}`,
  );

  // 1c. tools.ozone.set.getValues — read values from the set
  await tryEndpoint(
    result,
    "ozone.set.getValues",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcGet("tools.ozone.set.getValues", {
        name: setName,
        limit: 10,
      });
      const vals = body.values ?? [];
      return { name: body.set?.name ?? body.name, count: Array.isArray(vals) ? vals.length : "present" };
    },
    (r) => `name=${r.name}, count=${r.count}`,
  );

  // 1d. tools.ozone.set.querySets — list/query all sets
  await tryEndpoint(
    result,
    "ozone.set.querySets",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcGet("tools.ozone.set.querySets", {
        limit: 10,
      });
      const sets = body.sets ?? [];
      return { count: Array.isArray(sets) ? sets.length : "present" };
    },
    (r) => `sets=${r.count}`,
  );

  // 1e. tools.ozone.set.deleteValues — remove values from the set
  await tryEndpoint(
    result,
    "ozone.set.deleteValues",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.set.deleteValues", {
        name: setName,
        values: [`did:plc:testvalue1`],
      });
      return { status: "deleted" };
    },
  );

  // 1f. tools.ozone.set.deleteSet — remove the entire set
  await tryEndpoint(
    result,
    "ozone.set.deleteSet",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.set.deleteSet", {
        name: setName,
      });
      return { status: "deleted" };
    },
  );

  // ── 2. tools.ozone.team.* ─────────────────────────────────────────────
  // Team member management — add, list, update, and delete members.

  const testMemberDid = luna.did!;

  // 2a. tools.ozone.team.addMember — add a team member
  await tryEndpoint(
    result,
    "ozone.team.addMember",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.team.addMember", {
        did: testMemberDid,
        role: "tools.ozone.team.defs#roleViewer",
      });
      return { did: body.did ?? testMemberDid };
    },
    (r) => `did=${r.did}`,
  );

  // 2b. tools.ozone.team.listMembers — list team members
  await tryEndpoint(
    result,
    "ozone.team.listMembers",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcGet("tools.ozone.team.listMembers", {
        limit: 10,
      });
      const members = body.members ?? [];
      return { count: Array.isArray(members) ? members.length : "present" };
    },
    (r) => `members=${r.count}`,
  );

  // 2c. tools.ozone.team.updateMember — update member role
  await tryEndpoint(
    result,
    "ozone.team.updateMember",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.team.updateMember", {
        did: testMemberDid,
        role: "tools.ozone.team.defs#roleTriage",
      });
      return { did: body.did ?? testMemberDid };
    },
    (r) => `did=${r.did}`,
  );

  // 2d. tools.ozone.team.deleteMember — remove team member
  await tryEndpoint(
    result,
    "ozone.team.deleteMember",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.team.deleteMember", {
        did: testMemberDid,
      });
      return { status: "deleted" };
    },
  );

  // ── 3. tools.ozone.setting.* ──────────────────────────────────────────
  // Service settings — upsert options, list, and remove.

  const optionKey = "test-scenario-option-key";

  // 3a. tools.ozone.setting.upsertOption — create/update a setting option
  await tryEndpoint(
    result,
    "ozone.setting.upsertOption",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.setting.upsertOption", {
        key: optionKey,
        value: { $type: "tools.ozone.setting.defs#string", value: "test-value" },
        scope: "tools.ozone.setting.defs#scopePersonal",
      });
      return { key: body.key ?? optionKey };
    },
    (r) => `key=${r.key}`,
  );

  // 3b. tools.ozone.setting.listOptions — list all settings
  await tryEndpoint(
    result,
    "ozone.setting.listOptions",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcGet("tools.ozone.setting.listOptions", {
        limit: 10,
      });
      const options = body.options ?? [];
      return { count: Array.isArray(options) ? options.length : "present" };
    },
    (r) => `options=${r.count}`,
  );

  // 3c. tools.ozone.setting.removeOptions — remove settings
  await tryEndpoint(
    result,
    "ozone.setting.removeOptions",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.setting.removeOptions", {
        keys: [optionKey],
      });
      return { status: "removed" };
    },
  );

  // ── 4. tools.ozone.communication.* ─────────────────────────────────────
  // Communication templates for moderation outreach (email).

  const templateName = "test-scenario-template";
  const templateContent = "This is a test moderation notification template.";

  // 4a. tools.ozone.communication.createTemplate — create a template
  const templateRef = await tryEndpoint(
    result,
    "ozone.communication.createTemplate",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.communication.createTemplate", {
        name: templateName,
        contentMarkdown: templateContent,
        subject: "Test Moderation Notice",
        lang: "en",
        createdBy: luna.did,
      });
      return { id: body.id, name: body.name };
    },
    (r) => `id=${r.id}, name=${r.name}`,
  );

  // 4b. tools.ozone.communication.listTemplates — list all templates
  await tryEndpoint(
    result,
    "ozone.communication.listTemplates",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcGet("tools.ozone.communication.listTemplates", {});
      const templates = body.communicationTemplates ?? body.templates ?? [];
      return { count: Array.isArray(templates) ? templates.length : "present" };
    },
    (r) => `templates=${r.count}`,
  );

  // 4c. tools.ozone.communication.updateTemplate — update a template
  await tryEndpoint(
    result,
    "ozone.communication.updateTemplate",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.communication.updateTemplate", {
        id: templateRef?.id ?? "",
        name: templateName,
        contentMarkdown: `${templateContent}\n\nUpdated for coverage test.`,
        subject: "Updated: Test Moderation Notice",
        lang: "en",
        updatedBy: luna.did,
      });
      return { id: body.id, name: body.name };
    },
    (r) => `id=${r.id}`,
  );

  // 4d. tools.ozone.communication.deleteTemplate — delete a template (cleanup)
  await tryEndpoint(
    result,
    "ozone.communication.deleteTemplate",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("tools.ozone.communication.deleteTemplate", {
        id: templateRef?.id ?? "",
      });
      return { status: "deleted" };
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
