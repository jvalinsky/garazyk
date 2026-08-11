---
title: NixOS build and deployment
---

# NixOS build and deployment

How to build a Garazyk service from the repository flake and run it on NixOS.
The zuk relay is the reference service; the same pattern applies to the other
GNUstep binaries once they build against the toolchain.

## Where things are

| Path | Holds |
| --- | --- |
| `nix/toolchain.nix` | Linux GNUstep toolchain override used by the flake |
| `nix/patches/fixup-paths-master.patch` | Patch for the pinned `gnustep.base` build |
| `nixos/modules/zuk.nix` | `services.zuk` NixOS module (systemd unit + firewall) |
| `nixos/modules/cloudflared-tunnel.nix` | `services.cloudflaredTunnel` module (zero exposed ports) |
| `nixos/examples/relay.nix` | Dummy, non-server-specific composition of both modules |
| `flake.nix` | `packages.<system>.zuk`, `nixosModules.*`, devShells |

The modules are attached to the flake outside `eachDefaultSystem`, so they are
usable from any NixOS configuration regardless of the evaluation system.

## Build

`packages.zuk` and the Linux toolchain are gated on `stdenv.isLinux`; macOS can
evaluate them but only a Linux host can build. Build with:

```sh
nix build .#zuk
```

The derivation:

- filters the flake source with `cleanSourceWith` (drops `scripts/scenarios`,
  2+ GB, and `build/`, `node_modules/`, `coverage/`);
- configures with CMake (`Release`, `BUILD_TESTS=OFF`, `BUILD_FUZZERS=OFF`,
  `BUILD_SECP256K1=ON`) and builds only the `zuk` target with `--parallel 4`
  (unbounded builds exhaust memory on 16 GB hosts). The source fetch must include
  the `vendor/secp256k1` Git submodule;
- installs `build/bin/zuk` into `$out/bin`.

Before trusting a change to the pinned toolchain, re-run the local gates:

```sh
nix flake check --all-systems
nix run nixpkgs#nixpkgs-fmt -- --check flake.nix nix/ nixos/
```

### The GNUstep toolchain (`nix/toolchain.nix`)

- Pins `gnustep.base` at a specific `libs-base` master commit: the nixpkgs
  release build predates `NSJSONWritingSortedKeys`, which `GZJSON` needs, and
  bumping the `gnustep` package version to a commit that has it is not
  possible without rebuilding `gnustep.make`.
- Applies `nix/patches/fixup-paths-master.patch`, a rebased version of the
  `fixup-paths` patch used by the nixpkgs GNUstep package. It rewrites
  hardcoded Nix store paths baked into the master build. Rebase it whenever
  the pin moves; verify with `patch --dry-run`.
- Builds `libdispatch` standalone (no Swift toolchain on the host) and passes
  `--with-libcurl` to `gnustep-base` so `NSURLSession` builds.
- Exports `gnustepPrefix` and `runtimeLibs`; the devShells export the matching
  `GNUSTEP_PREFIX`, `GNUSTEP_MAKEFILES`, `LIBRARY_PATH`, `CPATH`, and
  `PKG_CONFIG_PATH`.

### CMakeLists gotcha

`CMakeLists.txt` must not exclude `WebSocketServer.m` on Linux. The
`SubscribeReposHandler` route pack requires the class, so zuk fails to link
with missing symbols when the exclusion is enabled. The Linux
`WebSocketServer` build is a prerequisite of the zuk package, not an optional
extra.

## Deploying on NixOS

A relay host (codename `bingus`) runs the services through the flake modules.
The repository carries only the reusable service modules and a dummy example;
the server-specific values (real tunnel ID, hostname, credentials file) live in
`/etc/nixos` and are never committed. The host flake should import the public
GitHub flake rather than a local Garazyk source checkout. Because the relay
package builds the `secp256k1` Git submodule, use the explicit Git fetch URL with
submodules enabled; the `github:` shorthand does not populate that submodule.

### `/etc/nixos` shape

Consume the public Garazyk GitHub flake as a pinned input. The host does not
need a local Garazyk source checkout:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    garazyk = {
      url = "git+https://github.com/jvalinsky/garazyk.git?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, garazyk }:
    let system = "x86_64-linux";
    in {
      nixosConfigurations.bingus = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix
          garazyk.nixosModules.zuk
          # Use this only if the host consumes the repository's optional
          # cloudflaredTunnel module; the bingus host instead imports its
          # native services/cloudflared.nix configuration.
          garazyk.nixosModules.cloudflaredTunnel
        ];
        specialArgs = {
          garazykPkgs = garazyk.packages.${system};
        };
      };
    };
}
```

Then enable the services. An empty `upstreams` list is intentional for a
passthrough relay: it starts without a configured PDS and accepts crawl requests
through the relay API or dashboard. Set explicit upstream URLs instead when this
host should aggregate a fixed set of PDS firehoses.

```nix
services.zuk = {
  enable = true;
  package = garazykPkgs.zuk;
  # Runtime secret path supplied by sops-nix, agenix, or equivalent. The
  # module passes it to zuk through a systemd credential, not the Nix store.
  adminPasswordFile = "/run/secrets/relay_admin_password";
  # port/dataDir/upstreams/validationMode all have safe defaults:
  # 2470, /var/lib/zuk, [] (passthrough --no-upstream), log-only
};

# Alternative when using garazyk.nixosModules.cloudflaredTunnel:
services.cloudflaredTunnel = {
  enable = true;
  tunnelId = "<real tunnel ID>";
  hostname = "relay.example.com";
  credentialsFile = "/var/lib/cloudflared/<tunnelId>.json";
  origin = "http://127.0.0.1:2470";
};

# The bingus host uses native NixOS cloudflared instead, in
# /etc/nixos/services/cloudflared.nix:
# services.cloudflared.tunnels.<tunnel-id> = { ... };
```

The module's systemd unit runs zuk as the `zuk` system user with
`ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`, and a hardened
address family set. The host firewall stays closed (`openFirewall` defaults to
`false`); the tunnel connects to the loopback, so no host port is exposed. Set
`adminPasswordFile` to a root-readable runtime secret. The module loads it with
systemd's credential mechanism and exposes only the credential path to zuk as
`RELAY_ADMIN_PASSWORD_FILE`.

The relay root URL redirects unauthenticated operators to `/login`. A successful
login creates an opaque, service-scoped HttpOnly session cookie; state-changing
controls also require a rotating one-time CSRF nonce. The authenticated dashboard
polls:

- `GET /api/relay/health` for status, sequence, and connection counts;
- `GET /api/relay/metrics` for event and validation counters;
- `GET /api/relay/upstreams` for configured hosts, crawl state, account counts,
  and sequence state.

It also exposes session-protected crawl/reconnect/disconnect actions and renders
a live `/xrpc/com.atproto.sync.subscribeRepos` event feed. Read-only telemetry
and relay protocol routes remain public for monitoring and federation.

### Procedure

```sh
# First edit /etc/nixos/flake.nix and change the garazyk input URL from
# `github:jvalinsky/garazyk` to:
# `git+https://github.com/jvalinsky/garazyk.git?submodules=1`
# Then update the pinned input. This fetches vendor/secp256k1 for the zuk build.
cd /etc/nixos
sudo nix flake lock --update-input garazyk
sudo nix flake metadata | sed -n '/garazyk:/,/^[^ ]/p'

# Build the locked package and system configuration without switching.
nix build /etc/nixos#nixosConfigurations.bingus.config.system.build.toplevel
sudo nixos-rebuild build --flake /etc/nixos#bingus

# Inspect the rendered unit before switching.
systemctl cat zuk

# Activate the new generation.
sudo nixos-rebuild switch --flake /etc/nixos#bingus
```

### Verification

For Zuk, use its relay health route rather than the PDS `/xrpc/_health` route:

```sh
systemctl status zuk --no-pager
curl -fsS http://127.0.0.1:2470/api/relay/health
# Unauthenticated dashboard requests should redirect to /login.
curl -fsSI https://relay.example.com/ | grep -i '^location: /login'
# Complete a dashboard login through a browser: https://relay.example.com/
# Run this from a Garazyk checkout containing scripts/monitor_relay_firehose.ts:
deno run -A scripts/monitor_relay_firehose.ts \
  --relay-url https://relay.example.com \
  --duration 30
```

On a headless host, replace `open` with a browser or `curl -I` check. A relay
change also deserves a crawl check: confirm the PDS announces the relay, inspect
`/api/relay/upstreams`, and verify that a `subscribeRepos` connection stays alive.
Roll back with the previous generation if startup or the public checks fail:

```sh
sudo nixos-rebuild switch --rollback
```

## Migration notes for the old relay

The previous deployment ran the reference `indigo` relay through the `nur`
package set with an admin password secret. On swap:

- remove the `nur` input and the indigo service from `/etc/nixos`;
- point `services.zuk.adminPasswordFile` at the existing relay admin-password
  secret, or provision a new runtime secret before switching;
- run `nixos-rebuild build` first, then `switch` when the health check passes.
