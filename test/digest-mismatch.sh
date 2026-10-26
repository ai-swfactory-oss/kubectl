#!/usr/bin/env bash
# Named test: a release binary whose sha256, or whose sha512, does not match
# the digest pinned in upstream.json fails scripts/fetch.sh, which the build
# runs before it stages, packs or publishes anything, naming the mismatch and
# leaving neither the download nor a staged binary behind. The same binary with
# both true digests is accepted and staged unchanged, so the check is not
# vacuous. Runs offline: the "release" is local files.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

digest_of() { # <algorithm 256|512> <file>
  if command -v "sha$1sum" >/dev/null 2>&1; then "sha$1sum" "$2" | cut -d' ' -f1; else shasum -a "$1" "$2" | cut -d' ' -f1; fi
}

path=bin/linux/amd64/kubectl
mkdir -p "$work/release/bin/linux/amd64"
printf 'not really kubectl\n' >"$work/release/$path"
printf '                                 Apache License\n                           Version 2.0, January 2004\n' >"$work/release/LICENSE"
true256=$(digest_of 256 "$work/release/$path")
true512=$(digest_of 512 "$work/release/$path")
wrong256=$(printf '%064d' 0)
wrong512=$(printf '%0128d' 0)

manifest() { # <sha256> <sha512>
  jq -n --arg p "$path" --arg d "sha256:$1" --arg s "$2" \
    '{version: "9.9.9", repack: 0, assets: {"linux-x64": {path: $p, digest: $d, sha512: $s}}}'
}

fetch() { # <manifest file> <outdir>
  UPSTREAM_JSON=$1 UPSTREAM_BASE_URL="file://$work/release" UPSTREAM_LICENSE_URL="file://$work/release/LICENSE" \
    bash "$root/scripts/fetch.sh" "$2"
}

expect_refusal() { # <case> <sha256> <sha512> <log pattern>
  manifest "$2" "$3" >"$work/$1.json"
  set +e
  fetch "$work/$1.json" "$work/out-$1" >"$work/$1.log" 2>&1
  local rc=$?
  set -e
  cat "$work/$1.log"
  test "$rc" -ne 0 || { echo "digest-mismatch: $1: fetch accepted a binary whose digest does not match" >&2; exit 1; }
  grep -q "$4" "$work/$1.log" || { echo "digest-mismatch: $1: the failure does not say '$4'" >&2; exit 1; }
  test ! -e "$work/out-$1/assets/kubectl-v9.9.9-linux-x64" || { echo "digest-mismatch: $1: the mismatching download was left behind" >&2; exit 1; }
  test ! -e "$work/out-$1/linux-x64" || { echo "digest-mismatch: $1: the mismatching binary was staged" >&2; exit 1; }
}

expect_refusal sha256 "$wrong256" "$true512" "sha256 mismatch for $path"
expect_refusal sha512 "$true256" "$wrong512" "sha512 mismatch for $path"

manifest "$true256" "$true512" >"$work/true.json"
fetch "$work/true.json" "$work/out-true"
cmp "$work/release/$path" "$work/out-true/linux-x64/kubectl"

echo "digest-mismatch: OK"
