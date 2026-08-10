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
  (unbounded builds exhaust memory on 16 GB hosts);
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
The repository carries only the reusable config and a dummy example; the
server-specific values (real tunnel ID, hostname, credentials file) live in
`/etc/nixos` and are never committed.

### `/etc/nixos` shape

Take the repository as a `path:` input rather than carrying the services in a
third-party channel:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    garazyk-src = {
      url = "path:/home/bingus/garazyk-src";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, garazyk-src }:
    let system = "x86_64-linux";
    in {
      nixosConfigurations.bingus = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix
          garazyk-src.nixosModules.zuk
          garazyk-src.nixosModules.cloudflaredTunnel
        ];
        specialArgs = {
          garazykPkgs = garazyk-src.packages.${system};
        };
      };
    };
}
```

Then enable the services:

```nix
services.zuk = {
  enable = true;
  package = garazykPkgs.zuk;
  # port/dataDir/upstreams/validationMode all have safe defaults:
  # 2470, /var/lib/zuk, [] (passthrough --no-upstream), log-only
};

services.cloudflaredTunnel = {
  enable = true;
  tunnelId = "<real tunnel ID>";
  hostname = "relay.example.com";
  credentialsFile = "/var/lib/cloudflared/<tunnelId>.json";
  origin = "http://127.0.0.1:2470";
};
```

The module's systemd unit runs zuk as the `zuk` system user with
`ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`, and a hardened
address family set. The host firewall stays closed (`openFirewall` defaults to
`false`); the tunnel connects to the loopback, so no host port is exposed.

### Procedure

```sh
# pull the new commit in the source checkout
cd /home/bingus/garazyk-src && git pull

# build the package and the config (does not touch the live system)
nix build .#zuk
sudo nixos-rebuild build

# inspect the rendered unit before switching
systemctl cat zuk

# then switch
sudo nixos-rebuild switch
```

### Verification

```sh
systemctl status zuk --no-pager
curl -fsS http://127.0.0.1:2470/xrpc/_health
# through the tunnel, from outside:
curl -fsS https://relay.example.com/xrpc/_health
```

A relay change also deserves a crawl check: confirm the PDS announces the relay
and that a `subscribeRepos` connection stays alive. Roll back with the previous
generation if startup or the public checks fail:

```sh
sudo nixos-rebuild switch --rollback
```

## Migration notes for the old relay

The previous deployment ran the reference `indigo` relay through the `nur`
package set with an admin password secret. On swap:

- remove the `nur` input and the indigo service from `/etc/nixos`;
- drop the `relay_admin_password` secret file reference (zuk takes no admin
  password);
- run `nixos-rebuild build` first, then `switch` when the health check passes.
