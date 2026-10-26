#!/usr/bin/env bash
# Single-quoted jq programs and Markdown backticks are literal on purpose.
# shellcheck disable=SC2016
# Renders the npm packages from the verified upstream release.
#
#   scripts/stage.sh <fetchdir> <outdir>
#
# <fetchdir> is the output of scripts/fetch.sh (every platform).
# Result: <outdir>/kubectl            the launcher (bin, binaryPath(), upstreamVersion)
#         <outdir>/kubectl-<platform> one package per platform binary
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
fetched=${1:?usage: stage.sh <fetchdir> <outdir>}
out=${2:?usage: stage.sh <fetchdir> <outdir>}

scope=@ai-swfactory-oss
repo_url=https://github.com/ai-swfactory-oss/kubectl.git
upstream=$(jq -er .version "$manifest")
version=$(bash "$root/scripts/pkgver.sh")
read -r -a platforms <<<"$(jq -r '.assets | keys | join(" ")' "$manifest")"

common='{
  license: "Apache-2.0",
  author: "ai-swfactory",
  homepage: "https://github.com/ai-swfactory-oss/kubectl#readme",
  bugs: { url: "https://github.com/ai-swfactory-oss/kubectl/issues" },
  repository: { type: "git", url: $repo },
  publishConfig: { registry: "https://npm.pkg.github.com" }
}'

notice() { # <package name> <binary line>
  cat "$root/packages/NOTICE.in"
  printf '\nThis package: %s %s, re-packaged from kubectl v%s.\n' "$1" "$version" "$upstream"
  printf 'Upstream release: https://github.com/kubernetes/kubernetes/releases/tag/v%s\n\n' "$upstream"
  printf '%s\n' "$2"
}

rm -rf "$out"
mkdir -p "$out"

optional='{}'
for platform in "${platforms[@]}"; do
  os=${platform%%-*}
  cpu=${platform#*-}
  binary=kubectl
  name="$scope/kubectl-$platform"
  url="https://dl.k8s.io/release/v$upstream/$(jq -er --arg p "$platform" '.assets[$p].path' "$manifest")"
  digest=$(jq -er --arg p "$platform" '.assets[$p].digest' "$manifest")
  dir="$out/kubectl-$platform"

  mkdir -p "$dir/bin"
  cp "$fetched/$platform/$binary" "$dir/bin/$binary"
  chmod 755 "$dir/bin/$binary"
  cp "$fetched/LICENSE" "$dir/LICENSE"
  notice "$name" "Binary: bin/$binary, the unmodified kubectl binary from $url ($digest)." >"$dir/NOTICE"
  {
    printf '# %s\n\n' "$name"
    printf 'The native [kubectl](https://kubernetes.io/docs/reference/kubectl/) v%s binary for `%s` / `%s`.\n\n' "$upstream" "$os" "$cpu"
    printf 'Do not install this package directly: install [`%s/kubectl`](https://github.com/ai-swfactory-oss/kubectl), which depends on it optionally and runs it.\n\n' "$scope"
    printf 'The binary is the unmodified `kubectl` from %s (`%s`).\n\n' "$url" "$digest"
    printf 'Provenance: `gh attestation verify bin/%s --repo ai-swfactory-oss/kubectl` (run in this package directory).\n\n' "$binary"
    printf 'License: Apache-2.0 (see `LICENSE` and `NOTICE`).\n'
  } >"$dir/README.md"

  jq -n --arg name "$name" --arg version "$version" --arg upstream "$upstream" \
    --arg os "$os" --arg cpu "$cpu" --arg binary "bin/$binary" --arg repo "$repo_url" \
    "{
      name: \$name,
      version: \$version,
      description: \"kubectl \(\$upstream) native binary for \(\$os)-\(\$cpu) (used by @ai-swfactory-oss/kubectl)\",
      keywords: [\"kubectl\", \"kubernetes\"],
      os: [\$os],
      cpu: [\$cpu],
      files: [\$binary, \"LICENSE\", \"NOTICE\", \"README.md\"],
      preferUnplugged: true
    } + $common" >"$dir/package.json"

  optional=$(jq -c --arg n "$name" --arg v "$version" '. + {($n): $v}' <<<"$optional")
done

launcher="$out/kubectl"
mkdir -p "$launcher"
cp -R "$root/packages/kubectl/." "$launcher/"
cp "$fetched/LICENSE" "$launcher/LICENSE"
notice "$scope/kubectl" "This package holds no binary: it runs the one from $scope/kubectl-<platform>-<arch>." >"$launcher/NOTICE"
jq --arg version "$version" --arg repo "$repo_url" --argjson optional "$optional" \
  ". + {version: \$version, optionalDependencies: \$optional} + $common" \
  "$root/packages/kubectl/package.json" >"$launcher/package.json"
chmod 755 "$launcher/bin/kubectl.js"

echo "stage: $version ($upstream) -> $out"
ls -1 "$out"
