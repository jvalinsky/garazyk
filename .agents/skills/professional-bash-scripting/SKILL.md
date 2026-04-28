---
name: professional-bash-scripting
description: Guide for writing maintainable, secure, and efficient bash scripts following industry best practices from Google, Greg's Wiki, and other authoritative sources.
---

# Professional Bash Scripting

Use this skill when writing or reviewing production bash scripts, CI/CD automation, multi-step operations, or scripts that handle user input, files, credentials, network calls, cleanup, or shared maintenance.

Do not use this skill for one-liners, aliases, throwaway local commands, or tasks where Python/Ruby would be a better fit because the logic has grown beyond shell's strengths.

## Core Workflow

1. Choose the right shell target: Bash for Bash-specific features, POSIX `sh` only when portability is required.
2. Start with strict execution: `set -euo pipefail`, clear traps, cleanup handling, and dependency checks.
3. Validate every external input before it reaches filesystem, command, network, or eval-like sinks.
4. Organize script logic into small functions with `local` variables, readonly constants, and a short `main` path.
5. Prefer arrays, quoting, safe temporary files, and whitelists over string-built commands.
6. Run ShellCheck and test success, failure, missing dependency, permission, path, and signal-handling cases.

## Quick Checklist

- [ ] Uses a correct shebang and strict shell options.
- [ ] Has cleanup traps for temporary files, locks, and interrupted runs.
- [ ] Uses explicit exit codes and writes errors to stderr.
- [ ] Validates arguments, paths, numeric ranges, and dependencies.
- [ ] Quotes expansions and uses arrays for command construction.
- [ ] Avoids `eval`, unsafe globbing, command injection, and untrusted path traversal.
- [ ] Keeps functions focused and uses `local` variables.
- [ ] Supports non-interactive execution and `NO_COLOR` when color is used.
- [ ] Has meaningful usage text and examples.
- [ ] Passes ShellCheck and task-specific tests.

## References

Read only the files needed for the task:

- [detailed-guidelines.md](references/detailed-guidelines.md): Shell options, traps, validation, organization, security, performance, logging, documentation, and testing patterns.
- [pitfalls.md](references/pitfalls.md): Common shell mistakes and safer replacements.
- [complete-example-script.md](references/complete-example-script.md): Full secure backup script example.
- [testing-and-performance.md](references/testing-and-performance.md): Test checklist and performance benchmark guidance.
- [bibliography.md](references/bibliography.md): Source references for bash style and safety guidance.
