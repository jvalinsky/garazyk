---
title: Workstream 11 Progress
status: active
last_verified: 2026-08-11
---

# Workstream 11 — Per-Service Admin UI: Progress Summary

## Completed this session (2026-08-11)

### Video (jelcz)

| Slice | Status | Commit |
|---|---|---|
| 1 — Snapshot (JelczAdminSnapshot) | ✅ | `6bdc4a5e` |
| 2 — Allowlisted DTO (job detail) | ✅ | `6bdc4a5e` |
| 3 — Embedded pack in jelcz binary | ✅ | `3254882b` |
| NixOS module | ✅ | `e2d74fa9` |
| Format-string crash fix (full overview) | ✅ | `6bdc4a5e`, `3254882b` |
| Deployment example | ✅ | `3254882b` |

### Ozone

| Slice | Status | Commit |
|---|---|---|
| Overview route (`/admin/partials/ozone`) | ✅ | earlier |
| DTO allowlisting (`renderOzoneConfigPartial`) | ✅ | `5d79e67b` |

### Chat (syrena-chat)

| Slice | Status | Commit |
|---|---|---|
| 1 — Privacy-safe overview | ✅ | `26cbfd51` |
| 2 — Allowlisted metadata + no plaintext previews | ✅ | `26cbfd51` |
| 3 — Embedded listener in syrena-chat binary | ✅ | `a359606e` |
| NixOS module | ✅ | `ec7db55f` |
| Deployment example | ✅ | `894673d9` |

### Germ

| Slice | Status | Commit |
|---|---|---|
| 1 — Aggregate counters (GermMailboxService) | ✅ | `1829b0cc` |
| 2 — Centralized pack (GZAdminUIGermPack) | ✅ | `f35ae5a6` |
| 3 — Embedded listener in germ binary | ✅ | `00057018` |
| NixOS module | ✅ | `22474f0f` |
| Deployment example | ✅ | `6079815d` |

### Syrena (AppView)

| Item | Status | Commit |
|---|---|---|
| NixOS module modernized to jelcz pattern | ✅ | `cf143642` |
| Deployment example | ✅ | `506bbc23` |

## Fleet-wide summary

| Service | Centralized pack | Embedded listener | NixOS module | Deploy example |
|---|---|---|---|---|
| Relay (zuk) | ✅ existing | ✅ existing | ✅ existing | ✅ relay.nix |
| PLC (campagnola) | ✅ existing | ✅ existing | ✅ existing | — |
| PDS (kaszlak) | ✅ existing | — | ✅ existing | — |
| AppView (syrena) | ✅ existing | ✅ existing | ✅ modernized | ✅ syrena.nix |
| Beskid | ✅ existing | ✅ existing | ✅ | — |
| Mikrus | ✅ existing | ✅ existing | ✅ | — |
| Video (jelcz) | ✅ + overview fix | ✅ new | ✅ new | ✅ jelcz.nix |
| Ozone | ✅ + DTO allowlist | — | — | — |
| Chat (syrena-chat) | ✅ + privacy-safe | ✅ new | ✅ new | ✅ syrena-chat.nix |
| Germ | ✅ new pack | ✅ new | ✅ new | ✅ germ.nix |

## Admin UI ports

| Service | Main port | Admin port |
|---|---|---|
| zuk (relay) | 2470 | 2594 |
| campagnola (PLC) | 2582 | 2592 |
| syrena (AppView) | 3200 | 2596 |
| beskid | 8085 | 2595 |
| mikrus | 3210 | 2593 |
| jelcz (Video) | 2586 | 2597 |
| syrena-chat | 2585 | 2598 |
| germ | 8082 | 2599 |
| garazyk-ui (centralized) | 2590 | — |

## Remaining work

| Service | Slices remaining |
|---|---|
| PDS (kaszlak) | All 6 slices — largest surface, existing packs need migration |
| Beskid | NixOS module exists; deploy example pending |
| Mikrus | NixOS module exists; deploy example pending |
| Ozone | Embedded listener if standalone binary created; NixOS module |
| Chat | Server-side admin endpoints for conversation/message data |
| Germ | Deploy germ + verify live metrics in browser |

## Build & test status

- **AllTests**: builds clean, 43/43 admin pack tests pass
- **All binaries**: germ, jelcz, syrena-chat, garazyk-ui all build clean
- **NixOS modules**: all 7 service modules pass `nix-instantiate --parse`
- **Deployment examples**: all 5 examples pass `nix-instantiate --parse`
