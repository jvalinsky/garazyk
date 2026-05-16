# Refactor 4: Unified Service Binary Entry Point

## Evidence

**9 service binaries** with duplicated patterns:

| Binary | Service | main.m Location | Pattern |
|--------|---------|-----------------|---------|
| `kaszlak` | PDS | `Sources/CLI/main.m` | Self-contained (arg parsing, crash handlers, setup) |
| `campagnola` | PLC | `Binaries/campagnola/main.m` | Self-contained |
| `zuk` | Relay | `Binaries/zuk/main.m` | Self-contained |
| `syrena` | AppView | `Binaries/syrena/main.m` | Delegates to `AppViewRuntime` |
| `syrena-chat` | Chat | `Binaries/syrena-chat/main.m` | Self-contained (+ PDSCrashReporter) |
| `mikrus` | Link Index | `Binaries/mikrus/main.m` | Delegates to `MikrusRuntime` |
| `garazyk-ui` | Admin UI | `Binaries/garazyk-ui/main.m` | Self-contained |
| `jelcz` | Video | `Binaries/jelcz/main.m` | Self-contained (+ PDSCrashReporter) |
| `germ` | E2EE Mailbox | `Binaries/germ/main.m` | Delegates to `GermRuntime` |

**Duplicated boilerplate across all binaries:**
- Crash signal handler installation (~50 lines) — 4 copies use raw signal handlers, 3 use `PDSCrashReporter`
- Argument parsing — each defines `parse_*_options()` with same `--port`, `--data-dir`, `--verbose`, `--help`
- `print_usage()` / `print_version()` / `fail_with_usage()` — every binary defines these
- Config loading — env vars, config file, or direct CLI, varying per service
- Runloop entry — `[[NSRunLoop currentRunLoop] run]` repeated everywhere

## Why It Matters

Creating a new AT Protocol service currently means:
1. Copy an existing `main.m`
2. Modify the arg parser (hope you didn't miss a flag)
3. Wire up crash handlers (choose the right pattern, hope it works)
4. Set up config loading (pick a strategy)
5. Register routes (hope you remember everything)

This is the first experience a new library consumer has — and it's a wall of copy-paste boilerplate. A unified entry point reduces "hello world" for a new service to ~50 lines.

## Proposed Solution

### `ServiceMain` Helper

```objc
// Shared/ServiceMain.h

typedef struct ServiceMainContext {
    const char *serviceName;       // e.g. "campagnola"
    uint16_t defaultPort;          // e.g. 2586
    bool usesConfigFile;           // whether --config is supported
    int  (^start)(ServiceMainContext *ctx, PDSConfiguration *config);
    void (^usage)(void);
} ServiceMainContext;

int ServiceMainRun(int argc, const char **argv, ServiceMainContext *ctx);
```

### Responsibilities of `ServiceMainRun`

1. Parse common flags (`--port`, `--data-dir`, `--verbose`, `--config`, `--help`, `--version`)
2. Install crash handlers (via `PDSCrashReporter` or `PDSSignalManager`)
3. Load configuration (from file or env)
4. Create `PDSConfiguration` object
5. Call `ctx->start(ctx, config)`
6. Enter `[[NSRunLoop currentRunLoop] run]`
7. Handle graceful shutdown (SIGTERM, SIGINT)

### Move `PDSCrashReporter` to `ATProtoCore`

Currently `PDSCrashReporter` is in `Compat/PlatformShims/CrashReporting/`. Every binary already links `ATProtoCore`. Moving it there means crash handlers are available automatically — no more raw signal handler copies.

## Target Binary main.m Size

After refactor, each `main.m` should be ~30-50 lines:

```objc
// Binaries/campagnola/main.m
int main(int argc, const char **argv) {
    ServiceMainContext ctx = {
        .serviceName = "campagnola",
        .defaultPort = 2586,
        .usesConfigFile = true,
        .start = ^int(ServiceMainContext *ctx, PDSConfiguration *config) {
            PLCServer *server = [[PLCServer alloc] initWithConfig:config];
            return [server startWithError:nil] ? 0 : 1;
        },
        .usage = ^{
            fprintf(stderr, "campagnola: PLC Directory Server\n");
            fprintf(stderr, "Usage: campagnola [--port PORT] [--data-dir PATH] ...\n");
        }
    };
    return ServiceMainRun(argc, argv, &ctx);
}
```

## Staging

| Step | Description | Rollback |
|------|-------------|----------|
| 1 | Move `PDSCrashReporter` into `ATProtoCore` (update CMakeLists.txt) | Revert file move |
| 2 | Define `ServiceMain` helper in `Shared/` | Revert file addition |
| 3 | Migrate `campagnola` (simplest binary) to new pattern | Revert campagnola/main.m |
| 4 | Migrate `zuk` (relay) to new pattern | Revert zuk/main.m |
| 5 | Migrate remaining self-contained binaries | Revert each |
| 6 | Migrate runtime-based binaries (syrena, mikrus, germ) | Revert each |
| 7 | Remove raw signal handler copies | Revert cleanup |
| 8 | Update `project.yml` and CMakeLists.txt for any path changes | Revert build changes |

## Dependencies

- None — self-contained change that only affects `main.m` files and the `ServiceMain` helper
- Can be done incrementally, binary by binary

## Characterization Tests

- Verify each binary starts with `--help` and prints usage
- Verify each binary starts with `--port X` and binds to port X
- Verify each binary handles SIGTERM gracefully
- Verify crash handler produces expected output on crash signal

## Confidence: Medium-High

The pattern is simple and well-understood. The main risk is edge cases in arg parsing differences between binaries — characterization tests mitigate this.
