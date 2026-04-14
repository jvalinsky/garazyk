# libclang setup for test-audit-validator

## Why setup matters

The clang-backed parser uses `github.com/go-clang/clang-v14`, which is a CGO
binding around libclang. That means the tool is not only compiling Go code. It
is also linking against clang libraries and relying on clang's idea of system
headers, frameworks, and resource directories.

If that environment is wrong, strict clang mode can fail even when the source
file itself is fine.

## Why CGO is required

The AST path is not implemented in pure Go. It calls libclang through CGO.

That is why the setup needs:

- clang headers for compilation
- libclang libraries for linking
- runtime library discovery so the binary can load libclang successfully

If you disable CGO, the clang-backed analysis path is unavailable.

## macOS setup

### Recommended: use Xcode's toolchain

```bash
xcode-select --install

export CGO_CFLAGS="-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include"
export CGO_LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib -Wl,-rpath,/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
```

Why this is recommended:

- the repository's Objective-C code is normally compiled against Apple's SDKs
- Xcode's clang, headers, frameworks, and runtime are aligned with one another
- the parser's fallback Objective-C arguments assume Xcode-style SDK paths on
  macOS

### Alternative: Homebrew LLVM

```bash
brew install llvm@14

export CGO_CFLAGS="-I$(brew --prefix llvm@14)/include"
export CGO_LDFLAGS="-L$(brew --prefix llvm@14)/lib -Wl,-rpath,$(brew --prefix llvm@14)/lib"
```

This can work well, but mixed environments deserve extra care. If your compile
commands point at Xcode's compiler while libclang comes from Homebrew or Nix,
you may need to set `CLANG_EXECUTABLE` and `CLANG_RESOURCE_DIR` explicitly so
the parsing runtime is internally consistent.

## Linux setup

### Ubuntu/Debian

```bash
sudo apt-get install libclang-14-dev clang-14

export CGO_CFLAGS="-I/usr/lib/llvm-14/include"
export CGO_LDFLAGS="-L/usr/lib/llvm-14/lib -Wl,-rpath,/usr/lib/llvm-14/lib"
```

### Fedora/RHEL

```bash
sudo dnf install clang-devel clang
```

On Linux, clang usually relies on system include paths rather than a macOS
SDK-style `-isysroot`, but the same rule still applies: parsing quality depends
on the headers and libraries matching the compiler runtime you actually use.

## Why Xcode headers and libraries must match

On macOS, headers, frameworks, and clang runtime files all come from the same
toolchain universe. Mixing them carelessly can produce parse failures that look
like source errors but are really environment mismatches.

Typical symptoms:

- Foundation or XCTest cannot be found
- strict clang mode fails while simple mode succeeds
- clang reports `ASTReadError`
- libclang works in one shell but not another

The safest approach is to use one coherent source for:

- `CGO_CFLAGS`
- `CGO_LDFLAGS`
- `CLANG_EXECUTABLE`
- `CLANG_RESOURCE_DIR`

## Why the Makefile exports `CGO_CFLAGS` and `CGO_LDFLAGS`

The repository Makefile is not just convenience wrapping. It encodes the
minimum environment the Go compiler needs to build the libclang-backed path.

On macOS it points at Xcode's toolchain:

- `CGO_CFLAGS` for clang headers
- `CGO_LDFLAGS` for clang libraries and runtime lookup

On Linux it points at the expected LLVM install tree.

That is why `make build` is the recommended local path. It keeps build flags
consistent with the repository's intended environment.

## Why the Nix shell sets `CLANG_EXECUTABLE` and `CLANG_RESOURCE_DIR`

The flake shell does more than install packages. It also sets environment
variables that help the parser recreate a stable clang runtime environment:

- `CLANG_EXECUTABLE`
- `LIBCLANG_PATH`
- `CLANG_RESOURCE_DIR`
- `CLANG_MODULE_CACHE_PATH`

Those matter because the parser sometimes consumes full compile commands from
`compile_commands.json`. If argv points at one compiler and libclang comes from
another runtime, parsing can fail even before AST extraction starts.

`CLANG_RESOURCE_DIR` is especially important because clang's builtin headers and
module resources live there. Without the right resource directory, parsing can
break in ways that look unrelated to the current source file.

## Repository helpers

### Makefile

```bash
cd tools/test-audit-validator
make build
make test
```

Use this when you want the repository's recommended build flags.

### Nix shell

```bash
cd tools/test-audit-validator
nix develop
make build
```

Use this when you want a repeatable environment with libclang, Go, and clang
runtime variables preconfigured.

## Verification

Start with the smallest useful checks:

```bash
cd tools/test-audit-validator

# Build the analysis package
go build ./internal/analysis/

# Run analysis package tests
go test ./internal/analysis/

# Run strict clang against a real tree
./bin/test-audit-validator analyze \
  --parser clang \
  --compile-commands-dir ../../build \
  ../../Garazyk/Tests
```

You can also inspect whether `pkg-config` can see libclang:

```bash
pkg-config --libs libclang
```

That is a useful signal, but the real verification is whether the tool can
create translation units for repository files under the same environment you
intend to use in practice.

## Why parse failures often mean argument mismatch, not broken code

A strict clang failure does not automatically mean the Objective-C file is bad.
Very often it means one of these is wrong:

- compile commands were missing
- compile commands came from the wrong build tree
- XCTest framework paths were missing
- SDK path and runtime path came from different toolchains
- resource directory was not set correctly

This is why `auto` mode is useful for day-to-day work and `clang` mode is best
used as a quality gate once the environment is known-good.

## Troubleshooting checklist

### `simple` mode works, `clang` mode fails

Likely cause:

- environment or argument mismatch, not rule logic

Check:

- `--compile-commands-dir` points at the correct out-of-source build
- `CGO_CFLAGS` and `CGO_LDFLAGS` match the libclang installation you expect
- `CLANG_EXECUTABLE` and `CLANG_RESOURCE_DIR` are coherent with that runtime

### `clang` mode fails with `ASTReadError`

Likely cause:

- compiler executable and libclang runtime came from different toolchains

Check:

- whether your shell mixes Xcode, Homebrew LLVM, or Nix LLVM
- whether `CLANG_EXECUTABLE` should be set explicitly

### Foundation or XCTest headers are missing

Likely cause:

- SDK or framework paths are missing from compile arguments

Check:

- that Xcode is installed on macOS
- that `compile_commands.json` comes from the intended build
- that the parser can find XCTest developer frameworks

## Alternative: skip CGO-backed tests

If you only need the non-clang parts of the tool, you can skip CGO-backed test
coverage:

```bash
go test -tags=no_cgo ./...
```

That is a fallback, not the preferred path for parser work.

## Read next

- [README.md](README.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/LIBCLANG_AST_PARSING.md](docs/LIBCLANG_AST_PARSING.md)
