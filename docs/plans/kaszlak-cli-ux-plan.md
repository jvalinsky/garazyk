# Better CLI UX for kaszlak (PDS CLI) - Detailed Plan

## Current State Analysis

### Existing CLI Commands
The CLI is located in `ATProtoPDS/Sources/CLI/` with the following structure:

| Command | File | Purpose |
|---------|------|---------|
| `help` | PDSCLIDispatcher.m | Show help |
| `version` | PDSCLIDispatcher.m | Show version |
| `serve` | PDSCLIServeCommand.m | Start PDS server |
| `account` | PDSCLIAccountCommand.m | Account management |
| `admin` | PDSCLIAdminCommand.m | Admin operations |
| `repo` | PDSCLIRepoCommand.m | Repository operations |
| `invite` | PDSCLIInviteCommand.m | Invite code management |
| `init` | PDSCLIInitCommand.m | Initialize PDS |
| `daemon` | PDSCLIDaemonCommand.m | Run as daemon |
| `nuke` | PDSCLINukeCommand.m | Delete data |
| `health` | PDSCLIHealthCommand.m | Health checks |
| `oauth` | PDSCLIOAuthCommand.m | OAuth operations |

### Renaming Required: september → kaszlak

Files that reference "september" that need renaming:
1. `PDSInstallerCommand.m` - executable path, data dir, log paths
2. `PDSBiometricKeychain.m` - service name, key type
3. `CappuccinoUI/package.json` - npm package name
4. `CappuccinoUI/package-lock.json` - npm package name

### Identified UX Gaps

1. **No subcommand grouping** - All commands at top level, no logical grouping
2. **Inconsistent argument parsing** - Some use positional, some use flags
3. **Missing shell completion** - No bash/zsh completion scripts
4. **No interactive mode** - Can't run in interactive REPL style
5. **Sparse `--help` output** - Commands lack detailed descriptions
6. **No config validation** - Config errors only shown at runtime
7. **No command aliases** - Long command names, no shortcuts like `pds s` for `serve`

---

## Implementation Plan

### Phase 1: Rename (High Priority, Quick Win)

**Tasks:**
1. Rename `september` → `kaszlak` in all source files
2. Update executable path `/usr/local/bin/september` → `/usr/local/bin/kaszlak`
3. Update data directory `~/.config/september` → `~/.config/kaszlak`
4. Update log paths
5. Update npm package name

**Files to modify:**
- `ATProtoPDS/Sources/Admin/PDSInstallerCommand.m`
- `ATProtoPDS/Sources/Security/PDSBiometricKeychain.m`
- `ATProtoPDS/Sources/App/CappuccinoUI/package.json`
- `ATProtoPDS/Sources/App/CappuccinoUI/package-lock.json`

### Phase 2: Command Grouping & Aliases

**Tasks:**
1. Implement subcommand groups:
   - `pds account` (already exists)
   - `pds admin` (already exists)
   - `pds repo` (already exists)
   - `pds server` (rename serve → server)
   - `pds system` (init, daemon, health)
2. Add command aliases:
   - `pds s` → `pds serve`
   - `pds a` → `pds account`
   - `pds i` → `pds invite`

**Implementation:** Add `aliases` method to PDSBaseCommand

### Phase 3: Enhanced Help & Documentation

**Tasks:**
1. Add detailed `helpText` for each command
2. Add examples section to help output
3. Add `--verbose` flag to show hidden options
4. Colorize output (when TTY detected)

**Implementation:** Update `PDSBaseCommand` and each command subclass

### Phase 4: Shell Completion Scripts

**Tasks:**
1. Generate bash completion script
2. Generate zsh completion script
3. Auto-install completion on `pds init`

**Files to create:**
- `scripts/completions/kaszlak.bash`
- `scripts/completions/kaszlak.zsh`

### Phase 5: Interactive Mode (Future)

**Tasks:**
1. Add `pds repl` command for interactive mode
2. Command history (readline)
3. Tab completion in REPL
4. Config editing mode

---

## Verification Checklist

- [ ] All "september" references renamed to "kaszlak"
- [ ] CLI builds without errors after rename
- [ ] `pds --help` works
- [ ] `pds serve --help` works
- [ ] Command aliases work (`pds s` → `pds serve`)
- [ ] Shell completion scripts work

---

## Notes

- The CLI is implemented in Objective-C using a custom command pattern
- Main entry point is `main.m` (GUI) and `server_main.m` (headless)
- CLI dispatcher is `PDSCLIDispatcher` which manages command registration and execution
- Configuration is loaded from `./config.json` by default