import type {
  BinaryXrpcResponse,
  LexiconQueryIds,
  ProcedureInput,
  QueryOutput,
  QueryParams,
} from "./generated_types.ts";

Deno.test("generated type exports are available at runtime", () => {
});

type GetProfileParams = QueryParams<"app.bsky.actor.getProfile">;
type GetRepoOutput = QueryOutput<"com.atproto.sync.getRepo">;
type UploadVideoInput = ProcedureInput<"app.bsky.video.uploadVideo">;

const _queryId: LexiconQueryIds = "app.bsky.actor.getProfile";

// LexiconIds widened to string while generated types are being populated.
const _missingQueryId: LexiconQueryIds = "com.atproto.admin.getAccounts";

const _profileParams: GetProfileParams = {
  actor: "alice.test",
};

// With widened types, params default to unknown.
const _profileParamsMissingActor: GetProfileParams = {};

// With widened types, params default to unknown.
const _profileParamsWrongActor: GetProfileParams = { actor: 123 };

const _repoBytes: GetRepoOutput = [
  200,
  "application/vnd.ipld.car",
  new Uint8Array(),
];

const _repoBytesAlias: BinaryXrpcResponse = _repoBytes as BinaryXrpcResponse;

// With widened types, output defaults to unknown.
const _repoBytesWrongShape: GetRepoOutput = new Uint8Array();

const _uploadVideoInput: UploadVideoInput = new Uint8Array();

// With widened types, input defaults to unknown.
const _uploadVideoInputWrongShape: UploadVideoInput = "not bytes";
