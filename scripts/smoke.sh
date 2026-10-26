#!/usr/bin/env bash
# The single-quoted node programs are literal on purpose.
# shellcheck disable=SC2016
# Named test, per platform: installs the packed tarballs into a scratch project,
# as a consumer would, and checks that binaryPath() resolves to an executable
# file that is the unmodified upstream binary, that `kubectl version --client`
# reports upstreamVersion, that a client-only command works, and that no
# tarball declares an install script.
#
#   scripts/smoke.sh <tgzdir> <platform>      e.g. dist/tgz linux-x64
#
# The binary is compared with a fresh, digest-verified download of the same
# upstream binary (scripts/fetch.sh). No cluster is contacted: KUBECONFIG
# points at an empty scratch file.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tgz=$(cd "${1:?usage: smoke.sh <tgzdir> <platform>}" && pwd)
platform=${2:?usage: smoke.sh <tgzdir> <platform>}
upstream=$(jq -er .version "$root/upstream.json")
version=$(bash "$root/scripts/pkgver.sh")

launcher="$tgz/ai-swfactory-oss-kubectl-$version.tgz"
native="$tgz/ai-swfactory-oss-kubectl-$platform-$version.tgz"

work=$(mktemp -d)
# Read tarball contents into files first: `tar ... | grep -q` under pipefail
# fails when the reader exits early and tar hits the closed pipe.
for f in "$launcher" "$native"; do
  test -f "$f" || { echo "smoke: missing $f" >&2; exit 1; }
  tar -xzOf "$f" package/package.json >"$work/package.json.scan"
  if jq -e '.scripts // {} | keys | any(test("install"))' "$work/package.json.scan" >/dev/null; then
    echo "smoke: $f declares an install script" >&2; exit 1
  fi
done

bash "$root/scripts/fetch.sh" "$work/upstream" "$platform"
reference="$work/upstream/$platform/kubectl"

mkdir -p "$work/project"
cd "$work/project" || exit 1
printf '{"name":"smoke","version":"1.0.0","private":true}\n' >package.json
npm install --no-audit --no-fund "$launcher" "$native"

export KUBECONFIG="$work/kubeconfig"
: >"$KUBECONFIG"

echo "== binaryPath(), upstreamVersion and kubectl version --client"
node -e '
  const { execFileSync } = require("node:child_process");
  const fs = require("node:fs");
  const kubectl = require("@ai-swfactory-oss/kubectl");
  const [expected, reference] = process.argv.slice(1);
  if (kubectl.upstreamVersion !== expected) throw new Error(`upstreamVersion ${kubectl.upstreamVersion} != ${expected}`);
  const bin = kubectl.binaryPath();
  if (!fs.statSync(bin).isFile()) throw new Error(`${bin} is not a file`);
  fs.accessSync(bin, fs.constants.X_OK);
  if (!fs.readFileSync(bin).equals(fs.readFileSync(reference))) throw new Error(`${bin} is not the verified upstream binary`);
  const report = JSON.parse(execFileSync(bin, ["version", "--client", "-o", "json"], { encoding: "utf8" }));
  const printed = report.clientVersion && report.clientVersion.gitVersion;
  if (printed !== `v${expected}`) throw new Error(`${bin} version --client reports ${printed}, expected v${expected}`);
  console.log(bin, printed);
' "$upstream" "$reference"

echo "== kubectl command: a client-only dry run"
bin="$work/project/node_modules/.bin/kubectl"
"$bin" create configmap smoke --from-literal=mode=patched --dry-run=client --validate=false -o yaml >configmap.yaml
cat configmap.yaml
grep -qx '  name: smoke' configmap.yaml || { echo "smoke: configmap name missing" >&2; exit 1; }
grep -qx '  mode: patched' configmap.yaml || { echo "smoke: configmap data missing" >&2; exit 1; }

echo "smoke: $platform OK"
