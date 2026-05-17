# Runner API Reference

Full API for the scenario runner infrastructure.

## ScenarioResult

The central object for tracking scenario outcomes.

```typescript
import { ScenarioResult } from "@garazyk/hamownia";

const result = new ScenarioResult("Human-Readable Name");
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `scenarioName` | `string` | Display name (set in constructor) |
| `steps` | `StepResult[]` | All recorded steps |
| `startedAt` | `number \| null` | Timestamp when `start()` was called |
| `finishedAt` | `number \| null` | Timestamp when `finish()` was called |
| `artifacts` | `Record<string, any>` | Arbitrary data for debugging/reports |
| `metadata` | `Record<string, any>` | Set by the runner (run_id, service_urls, etc.) |

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| `passed` | `number` | Count of passed steps |
| `failed` | `number` | Count of failed steps |
| `skipped` | `number` | Count of skipped steps |
| `total` | `number` | Total step count |
| `ok` | `boolean` | `true` if there are steps and none failed |

### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `start()` | `() => void` | Mark the scenario as started |
| `finish()` | `() => void` | Mark the scenario as finished |
| `stepPassed` | `(name, detail?, durationMs?) => StepResult` | Record a passed step |
| `stepFailed` | `(name, detail?, durationMs?) => StepResult` | Record a failed step |
| `stepSkipped` | `(name, detail?, durationMs?) => StepResult` | Record a skipped step |
| `recordArtifact` | `(name, data) => void` | Attach debugging data |
| `summary()` | `() => string` | Colored text summary |
| `printSummary()` | `() => void` | Print summary to stdout |
| `toReport()` | `() => object` | JSON-serializable report object |
| `writeReport` | `(dir, filename?) => Promise<string>` | Write JSON report to disk |

## timedCall

Wraps an async operation with step tracking, timing, and error handling.

```typescript
import { timedCall } from "@garazyk/hamownia";

const value = await timedCall(
  result,           // ScenarioResult to record the step on
  "Step name",      // Human-readable step name
  async () => {     // The operation
    return await someAsyncOperation();
  },
  (res) => `detail string with ${res.someField}`,  // Optional: detail from result
  false,            // Optional: expectFailure (default: false)
);
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `result` | `ScenarioResult` | required | Result object to record on |
| `name` | `string` | required | Step display name |
| `fn` | `() => Promise<T> \| T` | required | The operation to run |
| `detailFn` | `(res: T) => string` | undefined | Extract detail string from result |
| `expectFailure` | `boolean` | `false` | If true, success is a failure and failure is a pass |

### Return Value

- On success: the return value of `fn` (or `null` if `expectFailure` is true and it failed)
- On failure: `null` (the step is recorded as failed, execution continues)

### Behavior

- Measures wall-clock time with `performance.now()`
- On success: records `stepPassed` with duration
- On failure: records `stepFailed` with error message and duration
- When `expectFailure` is true: success → `stepFailed`, failure → `stepPassed`
- Never throws — errors are captured as step failures

## StepStatus

```typescript
enum StepStatus {
  PASSED = "passed",
  FAILED = "failed",
  SKIPPED = "skipped",
}
```

## StepResult

```typescript
class StepResult {
  constructor(
    public name: string,
    public status: StepStatus,
    public detail: string = "",
    public durationMs: number = 0,
  ) {}
}
```

## XrpcClient

```typescript
import { XrpcClient } from "@garazyk/gruszka";

const client = new XrpcClient("http://localhost:2583");
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `baseUrl` | `string` | Service base URL |
| `rawTransport` | `TransportLayer` | Low-level transport |
| `accounts` | `AccountsClient` | Account/session operations |
| `identity` | `IdentityClient` | Handle/DID resolution |
| `records` | `RecordsClient` | Record CRUD |
| `blobs` | `BlobsClient` | Blob upload/retrieval |
| `graph` | `GraphClient` | Follows/blocks/lists |
| `feed` | `FeedClient` | Timeline/feeds/posts |
| `notifications` | `NotificationsClient` | Notification management |
| `drafts` | `DraftsClient` | Draft CRUD |
| `search` | `SearchClient` | Search actors/posts |
| `contact` | `ContactClient` | Contact import/matching |
| `ageAssurance` | `AgeAssuranceClient` | Age assurance flows |
| `admin` | `AdminClient` | Admin operations |
| `raw` | `RawClient` | Raw XRPC get/post |
| `agent` | proxy | Agent-style API (createAccount, login, then method calls) |
| `lastResponse` | `object \| null` | Most recent HTTP response |
| `lastResponses` | `object[]` | Last 20 HTTP responses |

### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `healthCheck` | `() => Promise<boolean>` | Check `/_health` |
| `waitForHealthy` | `(timeout?) => Promise<void>` | Poll until healthy |
| `adminLogin` | `(password?) => Promise<string>` | Get admin JWT |

## TransportLayer

```typescript
import { TransportLayer } from "@garazyk/gruszka";

const transport = new TransportLayer("http://localhost:2583");
```

### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `get` | `(method, params?, token?) => Promise<any>` | XRPC query |
| `post` | `(method, body?, token?) => Promise<any>` | XRPC procedure |
| `postBinary` | `(method, data, contentType, token?) => Promise<any>` | Binary upload |
| `getBinary` | `(method, params?, token?, headers?) => Promise<[number, string, Uint8Array]>` | Binary download |
| `httpGet` | `(path, params?, token?) => Promise<any>` | Raw HTTP GET |
| `httpPost` | `(path, body?, token?) => Promise<any>` | Raw HTTP POST |

All methods throw `XrpcError` on HTTP 4xx/5xx responses. Built-in retry (3 attempts, exponential backoff).

## XrpcError

```typescript
class XrpcError extends Error {
  constructor(public method: string, public status: number, public body: any) {}
}
```

## Character

```typescript
import { getCharacter, getCharactersByRole, getCharactersByPds } from "@garazyk/hamownia";

const luna = getCharacter("luna");
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | `string` | Display name |
| `handle` | `string` | Handle (suffixed with hex timestamp) |
| `email` | `string` | Email (suffixed with hex timestamp) |
| `password` | `string` | Password |
| `persona` | `string` | Description for LLM-driven scenarios |
| `role` | `"user" \| "admin" \| "mod"` | Role |
| `pdsUrl` | `string` | PDS URL (PDS1 or PDS2) |
| `did` | `string` | Set after account creation |
| `accessJwt` | `string` | Set after account creation/login |
| `refreshJwt` | `string` | Set after account creation/login |
| `token` | `string` | Alias for `accessJwt` |

## Instrumentation

For load/soak scenarios:

```typescript
import { OperationTimer, PhaseTimer, scrapePrometheus, sampleStorage } from "@garazyk/hamownia";
```

| Utility | Description |
|---------|-------------|
| `OperationTimer` | Measure individual operation latencies |
| `PhaseTimer` | Measure scenario phases |
| `scrapePrometheus(url)` | Scrape Prometheus metrics from a service |
| `sampleStorage(dir)` | Snapshot storage usage |

## Mock Services

```typescript
import { MockTwilio } from "@garazyk/hamownia";
```

Used by phone verification scenarios. Starts a controllable mock Twilio server.
