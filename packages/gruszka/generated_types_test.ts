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

// @ts-expect-error exact query ids reject methods missing from generated lexicons.
const _missingQueryId: LexiconQueryIds = "com.atproto.admin.getAccounts";

const _profileParams: GetProfileParams = {
  actor: "alice.test",
};

// @ts-expect-error actor is required by app.bsky.actor.getProfile.
const _profileParamsMissingActor: GetProfileParams = {};

// @ts-expect-error actor must be a string.
const _profileParamsWrongActor: GetProfileParams = { actor: 123 };

const _repoBytes: GetRepoOutput = [
  200,
  "application/vnd.ipld.car",
  new Uint8Array(),
];

const _repoBytesAlias: BinaryXrpcResponse = _repoBytes;

// @ts-expect-error binary query outputs use the binary response tuple.
const _repoBytesWrongShape: GetRepoOutput = new Uint8Array();

const _uploadVideoInput: UploadVideoInput = new Uint8Array();

// @ts-expect-error binary procedure inputs are raw bytes, not JSON objects.
const _uploadVideoInputWrongShape: UploadVideoInput = "not bytes";
