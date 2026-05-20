import { assertEquals } from "@std/assert";
import {
  type GeneratedClient,
  generateInviteCode,
  type ProcedureInput,
  type ProcedureOutput,
  type QueryOutput,
  type QueryParams,
  RawClient,
  TransportLayer,
  XrpcClient,
} from "./mod.ts";
import { AccountsClient } from "./legacy_clients.ts";

Deno.test("gruszka root exposes generated and raw XRPC client primitives", () => {
  const client = new XrpcClient("http://localhost:2583");
  const generated: GeneratedClient = client.api;
  assertEquals(typeof generated, "object");
  assertEquals(typeof generated.app.bsky.actor.getProfile, "function");
  assertEquals(typeof client.query, "function");
  assertEquals(typeof client.procedure, "function");
  assertEquals(typeof TransportLayer, "function");
  assertEquals(typeof RawClient, "function");
  assertEquals(typeof generateInviteCode, "function");
});

Deno.test("gruszka legacy clients are available only through the explicit subpath", () => {
  assertEquals(typeof AccountsClient, "function");
});

type ProfileParams = QueryParams<"app.bsky.actor.getProfile">;
type ProfileOutput = QueryOutput<"app.bsky.actor.getProfile">;
type CreateAccountInput = ProcedureInput<"com.atproto.server.createAccount">;
type CreateAccountOutput = ProcedureOutput<"com.atproto.server.createAccount">;

const _profileParams: ProfileParams = { actor: "alice.test" };
const _profileOutput: ProfileOutput | undefined = undefined;
const _createAccountInput: CreateAccountInput = {
  handle: "alice.test",
  email: "alice@example.test",
  password: "password",
};
const _createAccountOutput: CreateAccountOutput | undefined = undefined;
