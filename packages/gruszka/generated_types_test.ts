import type {
  BinaryXrpcResponse,
  LexiconQueryIds,
  ProcedureInput,
  ProcedureOutput,
  QueryOutput,
  QueryParams,
} from "./generated_types.ts";

Deno.test("generated type exports are available at runtime", () => {
});

type GetProfileParams = QueryParams<"app.bsky.actor.getProfile">;
type GetRepoOutput = QueryOutput<"com.atproto.sync.getRepo">;
type UploadVideoInput = ProcedureInput<"app.bsky.video.uploadVideo">;
type CreateAccountOutput = ProcedureOutput<"com.atproto.server.createAccount">;
type CreateRecordOutput = ProcedureOutput<"com.atproto.repo.createRecord">;
type GetRecordOutput = QueryOutput<"com.atproto.repo.getRecord">;

const _queryId: LexiconQueryIds = "app.bsky.actor.getProfile";

// LexiconIds widened to string while generated types are being populated.
const _missingQueryId: LexiconQueryIds = "com.atproto.admin.getAccounts";

const _profileParams: GetProfileParams = {
  actor: "alice.test",
};

// @ts-expect-error The catalog requires an actor for getProfile.
const _profileParamsMissingActor: GetProfileParams = {};

// @ts-expect-error The catalog requires actor to be a string.
const _profileParamsWrongActor: GetProfileParams = { actor: 123 };

const _repoBytes: GetRepoOutput = [
  200,
  "application/vnd.ipld.car",
  new Uint8Array(),
];

const _repoBytesAlias: BinaryXrpcResponse = _repoBytes as BinaryXrpcResponse;

// @ts-expect-error Binary query output retains its binary response shape.
const _repoBytesWrongShape: GetRepoOutput = new Uint8Array();

const _uploadVideoInput: UploadVideoInput = new Uint8Array();

// @ts-expect-error Binary procedure input requires bytes.
const _uploadVideoInputWrongShape: UploadVideoInput = "not bytes";

// This mirrors the shape consumed by Hamownia's account-and-post smoke flow.
function _assertSmokeConsumerContract(
  createdAccount: CreateAccountOutput,
  createdRecord: CreateRecordOutput,
  readRecord: GetRecordOutput,
): void {
  const sessionDid: string = createdAccount.did;
  const sessionAccessJwt: string = createdAccount.accessJwt;
  const createdPostUri: string = createdRecord.uri;
  const readPostCid: string | undefined = readRecord.cid;
  void [sessionDid, sessionAccessJwt, createdPostUri, readPostCid];
}
