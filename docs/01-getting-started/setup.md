---
title: Setup
---

# Setup

## Install dependencies

On macOS:

```sh
brew install cmake deno xcodegen
```

On Debian or Ubuntu:

```sh
sudo apt install clang cmake libobjc-12-dev libsqlite3-dev libssl-dev gnustep-devel
```

Install Deno separately if your package manager does not provide it.

## Get the source

```sh
git clone https://github.com/jvalinsky/garazyk.git
cd garazyk
deno install
```

## Build and test

The CMake build works on macOS and Linux:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --gated=run
```

Run `xcodegen generate` before using the Xcode project on macOS.

The Deno checks are:

```sh
deno task check
deno task lint
deno task test
```

## Run a scenario

Docker must be running.

```sh
deno task hamownia run --setup 01_account_lifecycle
```

See the [scenario reference](../11-reference/deno-scenario-framework.md) for
other commands.

## Next

- [Codebase map](codebase-map.md)
- [Architecture](../20-explanation/architecture/atproto_pds_architecture.md)
- [Deployment](../20-explanation/guides/DEPLOYMENT.md)
