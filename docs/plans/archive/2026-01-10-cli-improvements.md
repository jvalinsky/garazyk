# CLI Improvements and Crash Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve CLI robustness, standardize command registration, and enhance UX with better help and consistent formatting.

**Architecture:** Move global argument parsing to a structured phase in `main.m`, delegate all command-related logic to `PDSCLIDispatcher`, and use Objective-C `+load` for decentralized command registration.

**Tech Stack:** Objective-C, Foundation, SQLite3.

### Task 1: Standardize Command Registration

**Files:**
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIRepoCommand.m`
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIDispatcher.m`

**Step 1: Add +load registration to PDSCLIRepoCommand**

```objective-c
// In ATProtoPDS/Sources/CLI/PDSCLIRepoCommand.m
@interface PDSRepoCommandRegistrar : NSObject
@end

@implementation PDSRepoCommandRegistrar
+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIRepoCommand alloc] init]];
}
@end
```

**Step 2: Remove manual registration from PDSCLIDispatcher**

```objective-c
// In ATProtoPDS/Sources/CLI/PDSCLIDispatcher.m
- (void)registerDefaultCommands {
    [self addCommand:[PDSCLIHelpCommand command]];
    [self addCommand:[PDSCLIVersionCommand command]];
    // Remove: [self addCommand:[PDSCLIRepoCommand command]];
}
```

**Step 3: Build and verify commands are still registered**

Run: `xcodebuild -scheme ATProtoPDS-CLI build`
Expected: Build passes. Run `./build/bin/atprotopds-cli` to see `repo` in help output.

**Step 4: Commit**

```bash
git add ATProtoPDS/Sources/CLI/PDSCLIRepoCommand.m ATProtoPDS/Sources/CLI/PDSCLIDispatcher.m
git commit -m "cli: use +load for repo command registration"
```

### Task 2: Robust Global Argument Parsing in main.m

**Files:**
- Modify: `ATProtoPDS/Sources/CLI/main.m`

**Step 1: Replace manual loops with safe parsing**

```objective-c
// In ATProtoPDS/Sources/CLI/main.m
// Replace the parsing loop with one that checks bounds before accessing args[i+1]
for (NSUInteger i = 0; i < args.count; i++) {
    NSString *arg = args[i];
    if (![arg hasPrefix:@"-"]) {
        firstCommandArg = i;
        break;
    }
    // Handle flags
    if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
        if (i + 1 < args.count) {
            context.dataDir = args[++i];
        } else {
            fprintf(stderr, "Error: --data-dir requires an argument\n");
            return 1;
        }
    }
    // ... repeat for --config, etc.
}
```

**Step 2: Delegate usage to Dispatcher**

Remove `print_usage()` from `main.m` and call `[[PDSCLIDispatcher sharedDispatcher] printUsage]` instead.

**Step 3: Verify crash fix**

Run: `./build/bin/atprotopds-cli --data-dir`
Expected: Error message instead of crash.

**Step 4: Commit**

```bash
git add ATProtoPDS/Sources/CLI/main.m
git commit -m "cli: fix out-of-bounds crash in global arg parsing"
```

### Task 3: Improve Account Command UX

**Files:**
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIAccountCommand.m`

**Step 1: Update helpText with required options**

```objective-c
// In ATProtoPDS/Sources/CLI/PDSCLIAccountCommand.m
- (NSString *)helpText {
    return @"Manage PDS accounts.\n\n"
           @"Subcommands:\n"
           @"  create --email <email> --handle <handle> [--password <pw>]  Create an account\n"
           // ... rest of subcommands
}
```

**Step 2: Add validation for create command**

Ensure email and handle are provided and basic format for handle (e.g., contains a dot) is checked before calling manager.

**Step 3: Commit**

```bash
git add ATProtoPDS/Sources/CLI/PDSCLIAccountCommand.m
git commit -m "cli: improve account command help and validation"
```
