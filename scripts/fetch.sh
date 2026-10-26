#!/usr/bin/env bash
# Downloads the upstream kubectl release binaries named in upstream.json from
# dl.k8s.io and verifies each against both digests pinned there: the sha256
# and the sha512 that dl.k8s.io publishes next to the binary (the update
# workflow pins them from those published checksum files). A binary whose
# digest does not match is deleted and the script exits 1, so nothing
# unverified is staged, packed or published.
#
#   scripts/fetch.sh <outdir> [platform ...]     (default: every platform)
#
# UPSTREAM_JSON overrides the manifest (default: upstream.json at the root);
# UPSTREAM_BASE_URL and UPSTREAM_LICENSE_URL override where the binaries and
# the LICENSE are downloaded from (the tests point them at local files).
#
# Result: <outdir>/assets/kubectl-v<version>-<platform>  (the upstream binary, as released)
#         <outdir>/<platform>/kubectl                    (the same bytes, executable)
#         <outdir>/LICENSE                               (kubernetes/kubernetes's LICENSE at the tag)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
out=${1:?usage: fetch.sh <outdir> [platform ...]}
shift

if [ "$#" -gt 0 ]; then
  platforms=("$@")
else
  read -r -a platforms <<<"$(jq -r '.assets | keys | join(" ")' "$manifest")"
fi

version=$(jq -er .version "$manifest")
base=${UPSTREAM_BASE_URL:-https://dl.k8s.io/release/v$version}

digest_of() { # <algorithm 256|512> <file>
  if command -v "sha$1sum" >/dev/null 2>&1; then
    "sha$1sum" "$2" | cut -d' ' -f1
  else
    shasum -a "$1" "$2" | cut -d' ' -f1
  fi
}

mkdir -p "$out/assets"
for platform in "${platforms[@]}"; do
  path=$(jq -er --arg p "$platform" '.assets[$p].path' "$manifest")
  digest=$(jq -er --arg p "$platform" '.assets[$p].digest' "$manifest")
  sha512=$(jq -er --arg p "$platform" '.assets[$p].sha512' "$manifest")
  case "$digest" in
    sha256:*) sha256=${digest#sha256:} ;;
    *) echo "fetch: $platform: digest '$digest' is not sha256:<hex>" >&2; exit 1 ;;
  esac
  [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "fetch: $platform: digest '$digest' is not sha256:<64 hex>" >&2; exit 1; }
  [[ "$sha512" =~ ^[0-9a-f]{128}$ ]] || { echo "fetch: $platform: sha512 '$sha512' is not 128 hex" >&2; exit 1; }

  asset="$out/assets/kubectl-v$version-$platform"
  echo "fetch: $platform <- $base/$path"
  curl -fsSL --retry 3 --retry-delay 5 -o "$asset" "$base/$path"

  for algorithm in 256 512; do
    if [ "$algorithm" = 256 ]; then expected=$sha256; else expected=$sha512; fi
    actual=$(digest_of "$algorithm" "$asset")
    if [ "$actual" != "$expected" ]; then
      echo "fetch: $platform: sha$algorithm mismatch for $path" >&2
      echo "  expected $expected" >&2
      echo "  actual   $actual" >&2
      rm -f "$asset"
      exit 1
    fi
    echo "fetch: $platform: sha$algorithm OK"
  done

  dest="$out/$platform"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$asset" "$dest/kubectl"
  chmod 755 "$dest/kubectl"
done

license_url=${UPSTREAM_LICENSE_URL:-https://raw.githubusercontent.com/kubernetes/kubernetes/v$version/LICENSE}
curl -fsSL --retry 3 --retry-delay 5 -o "$out/LICENSE" "$license_url"
if ! grep -q 'Apache License' "$out/LICENSE" || ! grep -q 'Version 2.0, January 2004' "$out/LICENSE"; then
  echo "fetch: the LICENSE at kubernetes/kubernetes v$version is not the expected Apache-2.0 text" >&2; exit 1
fi
