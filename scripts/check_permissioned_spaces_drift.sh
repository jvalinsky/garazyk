#!/usr/bin/env bash
# Verify the pinned Permissioned Data proposal and implementation branch.
#
# The script is read-only: a detected upstream change is reported and exits
# nonzero. Re-pin and regenerate lexicons only after recording the compatibility
# impact in docs/permissioned-spaces-compatibility.md.

set -euo pipefail

readonly PINNED_PROPOSAL_COMMIT="1caad93dbb1f445396f6abf3b97eb4040345e78e"
readonly PINNED_ATPROTO_COMMIT="3f6c96d5d2d25438bd40fa89d6ecc37865f8e354"
readonly PROPOSALS_REPOSITORY="https://github.com/bluesky-social/proposals.git"
readonly PROPOSAL_RAW_URL="https://raw.githubusercontent.com/bluesky-social/proposals"
readonly ATPROTO_API_URL="https://api.github.com/repos/bluesky-social/atproto"
readonly ATPROTO_RAW_URL="https://raw.githubusercontent.com/bluesky-social/atproto"
readonly PR_URL="${ATPROTO_API_URL}/pulls/5187"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'error: required command is unavailable: %s\n' "$command_name" >&2
    exit 2
  fi
}

fetch() {
  curl --fail --silent --show-error --location "$1"
}

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

pr_head_commit() {
  fetch "$PR_URL" | deno eval '
    const pull = await new Response(Deno.stdin.readable).json();
    if (typeof pull.head?.sha !== "string") Deno.exit(1);
    console.log(pull.head.sha);
  '
}

tree_paths() {
  local commit="$1"
  fetch "${ATPROTO_API_URL}/git/trees/${commit}?recursive=1" | deno eval '
    const tree = await new Response(Deno.stdin.readable).json();
    if (!Array.isArray(tree.tree)) Deno.exit(1);
    const paths = tree.tree
      .filter((entry) => typeof entry.path === "string")
      .map((entry) => entry.path)
      .filter((path) => /^lexicons\/com\/atproto\/(space|simplespace)\/.*\.json$/.test(path))
      .map((path) => path.slice("lexicons/".length))
      .sort();
    console.log(paths.join("\n"));
  '
}

local_lexicon_paths() {
  local repository_root="$1"
  local lexicon_root="${repository_root}/Garazyk/Resources/lexicons"
  find "${lexicon_root}/com/atproto/space" "${lexicon_root}/com/atproto/simplespace" \
    -type f -name '*.json' -print |
    sed "s#${lexicon_root}/##" |
    sort
}

compare_local_lexicons() {
  local repository_root="$1"
  local lexicon_root="${repository_root}/Garazyk/Resources/lexicons"
  local failed=0
  local lexicon_path

  while IFS= read -r lexicon_path; do
    local local_sum
    local remote_sum
    local_sum=$(sha256_stream < "${lexicon_root}/${lexicon_path}")
    remote_sum=$(fetch "${ATPROTO_RAW_URL}/${PINNED_ATPROTO_COMMIT}/lexicons/${lexicon_path}" | sha256_stream)
    if [[ "$local_sum" != "$remote_sum" ]]; then
      printf 'lexicon content differs from pin: %s\n' "$lexicon_path" >&2
      failed=1
    fi
  done < <(local_lexicon_paths "$repository_root")

  return "$failed"
}

main() {
  local repository_root
  local proposal_head
  local implementation_head
  local failed=0

  for command_name in curl deno diff find git sed sort awk; do
    require_command "$command_name"
  done
  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    printf 'error: required SHA-256 command is unavailable (shasum or sha256sum)\n' >&2
    exit 2
  fi

  repository_root=$(git rev-parse --show-toplevel)
  proposal_head=$(git ls-remote "$PROPOSALS_REPOSITORY" HEAD | awk 'NR == 1 { print $1 }')
  implementation_head=$(pr_head_commit)

  printf 'Permissioned Data drift check (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'proposal:       pinned=%s current=%s\n' "$PINNED_PROPOSAL_COMMIT" "$proposal_head"
  printf 'implementation: pinned=%s current=%s (atproto PR #5187)\n' "$PINNED_ATPROTO_COMMIT" "$implementation_head"

  if [[ "$proposal_head" != "$PINNED_PROPOSAL_COMMIT" ]]; then
    printf '\nProposal README drift:\n' >&2
    if ! diff -u \
      <(fetch "${PROPOSAL_RAW_URL}/${PINNED_PROPOSAL_COMMIT}/0016-permissioned-data/README.md") \
      <(fetch "${PROPOSAL_RAW_URL}/${proposal_head}/0016-permissioned-data/README.md"); then
      failed=1
    fi
  fi

  if [[ "$implementation_head" != "$PINNED_ATPROTO_COMMIT" ]]; then
    printf '\nImplementation lexicon-path drift:\n' >&2
    if ! diff -u <(tree_paths "$PINNED_ATPROTO_COMMIT") <(tree_paths "$implementation_head"); then
      failed=1
    fi
  fi

  if ! diff -u <(local_lexicon_paths "$repository_root") <(tree_paths "$PINNED_ATPROTO_COMMIT"); then
    printf 'local lexicon path set differs from the pinned implementation\n' >&2
    failed=1
  fi
  if ! compare_local_lexicons "$repository_root"; then
    failed=1
  fi

  if (( failed != 0 )); then
    printf '\nDrift found. Do not regenerate or re-pin automatically; record the compatibility impact first.\n' >&2
    exit 1
  fi
  printf 'No proposal, implementation, or vendored-lexicon drift detected.\n'
}

main "$@"
