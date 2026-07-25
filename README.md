# Garazyk

Garazyk is an Objective-C implementation of AT Protocol services. It runs on
macOS and on Linux with GNUstep.

The repository includes a Personal Data Server, relay, PLC directory, AppView,
and a small administration interface. These services can run separately or as a
local network. The project is under active development.

## Build

Install the platform dependencies described in the
[setup guide](docs/01-getting-started/setup.md), then run:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --gated=run
```

The Deno checks are:

```sh
deno task check
deno task lint
deno task test
```

To start the local Docker network:

```sh
./scripts/scenarios/setup_local_network.sh
```

## Documentation

Start with the [documentation index](docs/index.md). The main references are:

- [Contributor setup](docs/01-getting-started/setup.md)
- [Codebase map](docs/01-getting-started/codebase-map.md)
- [Architecture](docs/20-explanation/architecture/atproto_pds_architecture.md)
- [Deployment](docs/20-explanation/guides/DEPLOYMENT.md)
- [Scenario framework](docs/11-reference/deno-scenario-framework.md)

The services use plain HTTP. Production deployments need TLS termination through
a reverse proxy.

## License

Original project code is available under `Unlicense OR CC0-1.0`. Vendored code
keeps its upstream license. See [UNLICENSE](UNLICENSE), [LICENSES](LICENSES/),
and the SPDX headers in each source file.
