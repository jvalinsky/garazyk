#!/usr/bin/env bash
set -Eeuo pipefail

# Swap the staged NixOS configuration into place and activate it.
# This script intentionally does not run automatically when copied to bingus.

SRC="${SRC:-$HOME/zuk-swap}"
TARGET="${TARGET:-/etc/nixos}"
HOST="${HOST:-bingus}"
STAMP="$(date +%Y%m%d-%H%M%S)"
STAGED="${TARGET}.new-${STAMP}"
BACKUP="${TARGET}.before-zuk-${STAMP}"
FAILED_TARGET="${TARGET}.failed-${STAMP}"

rollback_needed=0

cleanup() {
  if [[ "$rollback_needed" -ne 1 || ! -d "$BACKUP" ]]; then
    return
  fi

  echo "Rebuild failed; restoring the previous configuration" >&2
  if [[ -e "$TARGET" ]]; then
    echo "Preserving failed configuration at $FAILED_TARGET" >&2
    if ! sudo mv "$TARGET" "$FAILED_TARGET"; then
      echo "ERROR: Could not move failed configuration aside; manual recovery is required." >&2
      return
    fi
  fi
  if ! sudo mv "$BACKUP" "$TARGET"; then
    echo "ERROR: Could not restore $BACKUP to $TARGET; manual recovery is required." >&2
    return
  fi
  echo "Previous configuration restored. No further rebuild was attempted." >&2
}
trap cleanup EXIT

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "$(id -u)" -ne 0 ]] || fail "Run this script as the bingus user without sudo: ~/swap_bingus_nixos_config.sh"
[[ -d "$SRC" ]] || fail "Staged configuration directory does not exist: $SRC"
[[ -f "$SRC/flake.nix" ]] || fail "Missing $SRC/flake.nix"
[[ -f "$SRC/configuration.nix" ]] || fail "Missing $SRC/configuration.nix"
[[ -f "$SRC/hardware-configuration.nix" ]] || fail "Missing $SRC/hardware-configuration.nix"
command -v nix >/dev/null || fail "nix is not available"
command -v nixos-rebuild >/dev/null || fail "nixos-rebuild is not available"
command -v rsync >/dev/null || fail "rsync is not available"

[[ ! -e "$STAGED" ]] || fail "Temporary staging path already exists: $STAGED"
[[ ! -e "$BACKUP" ]] || fail "Backup path already exists: $BACKUP"
[[ ! -e "$FAILED_TARGET" ]] || fail "Failed-target path already exists: $FAILED_TARGET"

if [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
  fail "Target exists but is not a directory: $TARGET"
fi

# Keep the source tree's ownership and mode out of /etc/nixos; root owns the
# active system configuration, and rsync --delete removes stale relay.nix files.
echo "Staging $SRC -> $STAGED"
sudo install -d -m 0755 -o root -g root "$STAGED"
sudo rsync -a --delete --no-owner --no-group "$SRC/" "$STAGED/"
sudo chown -R root:root "$STAGED"

# Evaluate the staged flake before touching the active configuration.
echo "Validating staged flake"
sudo nix flake metadata "$STAGED" >/dev/null
sudo nix eval --raw "$STAGED#nixosConfigurations.$HOST.config.networking.hostName" >/dev/null

# Preserve the complete old tree and atomically put the staged tree in place.
# Mark rollback as needed before either move: if the second move fails, the
# first move may already have left the machine without /etc/nixos.
rollback_needed=1
echo "Backing up $TARGET -> $BACKUP"
if [[ -e "$TARGET" ]]; then
  sudo mv "$TARGET" "$BACKUP"
fi
sudo mv "$STAGED" "$TARGET"

# The flake uses garazyk-src as a local path input. Refresh its lock after the
# swap so the active tree points at the current source checkout.
echo "Refreshing the garazyk-src path lock"
sudo nix flake lock --update-input garazyk-src "$TARGET"

# Build and activate. If this fails, the EXIT trap restores the old config.
echo "Rebuilding NixOS configuration for $HOST"
sudo nixos-rebuild switch --flake "$TARGET#$HOST" --show-trace

# The new generation is active; retain the old tree as a rollback copy.
rollback_needed=0

echo "Verifying zuk.service"
systemctl is-active --quiet zuk.service || fail "zuk.service is not active"
systemctl --no-pager --full status zuk.service | sed -n '1,30p'

if command -v curl >/dev/null; then
  echo "Verifying local relay health"
  curl --fail --silent --show-error --max-time 10 \
    http://127.0.0.1:2470/api/relay/health
  echo
fi

echo "Activation succeeded."
echo "Previous configuration preserved at: $BACKUP"
