# CLI Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the `help` command crash and modernize the CLI to support the single-tenant database architecture and provide better repository visibility.

**Architecture:** 
- Centralize command lookup in `PDSCLIDispatcher`.
- Update `PDSAccountManager` to use standard service database paths.
- Add a new `PDSCLIRepoCommand` that leverages `PDSRepositoryService` and `ActorStore`.

**Tech Stack:** Objective-C, SQLite, Foundation.

---

### Task 1: Fix `help` Command Crash

**Files:**
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIDispatcher.h`
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIDispatcher.m`

**Step 1: Expose command lookup in `PDSCLIDispatcher.h`**
Add: `- (nullable id<PDSCLICommand>)commandForName:(NSString *)name;`

**Step 2: Implement command lookup in `PDSCLIDispatcher.m`**
```objectivec
- (id<PDSCLICommand>)commandForName:(NSString *)name {
    return self.commands[name];
}
```

**Step 3: Update `PDSCLIHelpCommand` execution**
Replace `valueForKey:` with `commandForName:`.

**Step 4: Build and verify**
Run: `xcodebuild -scheme ATProtoPDS-CLI build`
Run: `./build/bin/atprotopds-cli help account`
Expected: Output showing usage for the account command.

---

### Task 2: Modernize Database Paths

**Files:**
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIAccountCommand.m`

**Step 1: Update `databasePathForContext:` logic**
```objectivec
+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context {
    NSDictionary *config = [context loadConfig];
    NSString *dataDir = context.dataDir;
    if (config[@"pds"][@"data_dir"]) {
        dataDir = config[@"pds"][@"data_dir"];
    }
    // New path: data/service/service.db
    return [[dataDir stringByAppendingPathComponent:@"service"] stringByAppendingPathComponent:@"service.db"];
}
```

**Step 2: Verify account listing**
Run: `./build/bin/atprotopds-cli account list`
Expected: Table showing accounts from the current session.

---

### Task 3: Implement Repository Inspection

**Files:**
- Create: `ATProtoPDS/Sources/CLI/PDSCLIRepoCommand.m`
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIDispatcher.m`

**Step 1: Implement `PDSCLIRepoCommand`**
Provide subcommands: `list <did>`, `get <did> <uri>`, `root <did>`.
Use `PDSDatabasePool` and `ActorStore` to fetch data.

**Step 2: Register command in `PDSCLIDispatcher.m`**
Add `[self addCommand:[PDSCLIRepoCommand command]];` to `registerDefaultCommands`.

**Step 3: Verify**
Run: `./build/bin/atprotopds-cli repo list <did>`
Expected: List of record URIs and CIDs.

---

### Task 4: Standardize Options and Cleanup

**Files:**
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIHealthCommand.m`
- Modify: `ATProtoPDS/Sources/CLI/PDSCLIInviteCommand.m`

**Step 1: Ensure all commands respect `--json`**
**Step 2: Verify `--verbose` enables `PDS_LOG_INFO`**
