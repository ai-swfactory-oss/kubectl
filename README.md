# kubectl

[![update](https://github.com/ai-swfactory-oss/kubectl/actions/workflows/update.yml/badge.svg)](https://github.com/ai-swfactory-oss/kubectl/actions/workflows/update.yml)
[![build](https://github.com/ai-swfactory-oss/kubectl/actions/workflows/build.yml/badge.svg)](https://github.com/ai-swfactory-oss/kubectl/actions/workflows/build.yml)

[kubectl](https://kubernetes.io/docs/reference/kubectl/), the Kubernetes command-line tool, as npm packages: the **native upstream binary** per platform, updated and published automatically to GitHub Packages. No download at install time, no install scripts.

| Package | What |
|---|---|
| `@ai-swfactory-oss/kubectl` | Thin: the `kubectl` bin, and `binaryPath()` / `upstreamVersion` for Node. Depends optionally on the four platform packages, pinned exactly. |
| `@ai-swfactory-oss/kubectl-linux-x64` | `bin/kubectl` from `https://dl.k8s.io/release/v<ver>/bin/linux/amd64/kubectl` |
| `@ai-swfactory-oss/kubectl-linux-arm64` | `bin/kubectl` from `https://dl.k8s.io/release/v<ver>/bin/linux/arm64/kubectl` |
| `@ai-swfactory-oss/kubectl-darwin-x64` | `bin/kubectl` from `https://dl.k8s.io/release/v<ver>/bin/darwin/amd64/kubectl` |
| `@ai-swfactory-oss/kubectl-darwin-arm64` | `bin/kubectl` from `https://dl.k8s.io/release/v<ver>/bin/darwin/arm64/kubectl` |

npm installs only the platform package whose `os`/`cpu` match. Each binary is the unmodified `kubectl` from dl.k8s.io, verified against the sha256 and the sha512 pinned in [`upstream.json`](upstream.json), both taken from the checksum files dl.k8s.io publishes next to the binary. Windows is not packaged (the ruling scope is darwin and linux).

## Install

The packages live on GitHub Packages, which needs two things even for public packages.

1. The scope line, in your project's `.npmrc` (safe to commit):

   ```
   @ai-swfactory-oss:registry=https://npm.pkg.github.com
   ```

2. A token with `read:packages` (a classic personal access token), in your **user** `~/.npmrc`, never in the repository:

   ```
   //npm.pkg.github.com/:_authToken=<token>
   ```

   In GitHub Actions, use `actions/setup-node` with `registry-url: https://npm.pkg.github.com`, `scope: "@ai-swfactory-oss"` and `NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`, and grant the job `packages: read`.

Then:

```sh
npm install --save-dev @ai-swfactory-oss/kubectl
npx kubectl version --client
```

## Use from Node

```js
const { spawnSync } = require('node:child_process');
const { binaryPath, upstreamVersion } = require('@ai-swfactory-oss/kubectl');

spawnSync(binaryPath(), ['apply', '--dry-run=client', '-f', 'manifest.yaml'], { stdio: 'inherit' });
```

- `binaryPath()` returns the absolute path of the native binary for this os and cpu. It throws `UnsupportedPlatformError` (with `platform` and `arch`) when no binary is published for them, and `PlatformPackageMissingError` when one is but its package is not installed.
- `upstreamVersion` is the kubectl version, for example `1.37.1` (`kubectl version --client` reports `v1.37.1`).

Installing with `--omit=optional` (or `--no-optional`) leaves no binary; `kubectl` then says so and exits 1.

## Verify what you installed

The binaries are **upstream's release binaries, unmodified**. `scripts/fetch.sh` downloads each one from dl.k8s.io and refuses it unless both its sha256 and its sha512 match the digests pinned in [`upstream.json`](upstream.json). The update workflow pins those from dl.k8s.io's published `.sha256` and `.sha512` files and checks that both match the same downloaded bytes. Nothing is rebuilt.

Every publish run also creates **GitHub build-provenance attestations** for each npm tarball and each `kubectl` binary it publishes:

```sh
gh attestation verify node_modules/@ai-swfactory-oss/kubectl-linux-x64/bin/kubectl \
  --repo ai-swfactory-oss/kubectl \
  --signer-workflow ai-swfactory-oss/kubectl/.github/workflows/build.yml
```

To tie a binary back to upstream yourself, check its sha256 against the digest in the platform package's `NOTICE` and against `https://dl.k8s.io/release/v<ver>/bin/<os>/<arch>/kubectl.sha256`. Each GitHub release here also carries the original upstream binaries.

The attestation proves that this repository's `build.yml` packaged the file from the named commit. It does not say who compiled kubectl: upstream did, and the pinned digests tie the binary to upstream's release.

## Versions

- The package version **equals the kubectl version** (`1.37.1`), for all five packages.
- A **re-pack** of the same kubectl release (a packaging fix only, rare) is published as `<version>-r.<n>`, for example `1.37.1-r.1`. You get one by setting `"repack": <n>` in `upstream.json`.
  - Semver orders `1.37.1-r.1` *below* `1.37.1`, so the publish job always passes the explicit dist-tag `latest`.
  - A range like `^1.37.1` does not select a re-pack; pin it exactly if you need it.
- Every published version has a GitHub release `v<package version>`.
- `packages/kubectl/package.json` carries no `version`: `scripts/stage.sh` sets it from `upstream.json` when it renders the launcher.

## How it stays up to date (no maintenance)

| Workflow | When | What |
|---|---|---|
| `update` | Daily 04:23 UTC; keepalive on the 1st of each month | Reads dl.k8s.io's stable channel (`release/stable.txt`). If it names a newer kubectl than `upstream.json`, it rewrites `upstream.json` with the four binary paths and the sha256 and sha512 dl.k8s.io publishes for them, after downloading each binary once and checking it matches both. It opens a pull request from `update/kubectl-<version>`, then builds and tests that branch on every platform. Separately, if the GitHub release for main's version is missing, it runs `build` with publishing, so a failed publish is retried the next day. |
| `build` | Push to `main` touching `upstream.json`, `scripts/`, `packages/`, `test/` or the workflow; manual; called by `update` | Runs the named digest-mismatch test, fetches the four binaries (failing on any sha256 or sha512 mismatch), stages the packages, runs the launcher tests and packs once. Each platform runner installs the packed tarballs into a scratch project. There it checks `binaryPath()`, that the binary equals a freshly verified download, `kubectl version --client`, and a client-only `kubectl create configmap --dry-run=client`. Publishing (never on pull requests) attests every tarball and binary, then pushes the tested tarballs to GitHub Packages, platform packages first, skipping versions that already exist. Last, it creates the release. |
| `pr` | Every pull request | `build` without publishing. |
| `failures` | After every `update` or `build` run on `main` | A failure opens one issue labelled `build-failure` (or comments on the open one); the next successful run closes it. |

A failing run publishes nothing new; the previous versions keep being served. Each release carries the npm tarballs as published, the original upstream binaries and `SHA256SUMS` over all of them.

## Local build

```sh
bash test/digest-mismatch.sh                     # named test, offline
bash scripts/fetch.sh build/upstream             # download + verify
bash scripts/stage.sh build/upstream build/npm   # render the packages
env KUBECTL_LAUNCHER_DIR=build/npm/kubectl node --test test/launcher.test.js
npm pack ./build/npm/kubectl ./build/npm/kubectl-*/ --pack-destination dist/tgz
bash scripts/smoke.sh dist/tgz darwin-arm64      # install and test like CI
```

`bash scripts/validate.sh` runs all of that for this machine's platform; it is the gate's validate command. Needs `bash`, `curl`, `jq`, `tar`, `shellcheck` and Node.

## License

- The scripts and workflows in this repository are **MIT** (see [`LICENSE`](LICENSE)).
- The **npm packages are Apache-2.0**, the license of kubectl (Copyright The Kubernetes Authors). Each package ships the upstream `LICENSE` and a `NOTICE`. Upstream ships no `NOTICE` file of its own; the binary is not modified.

This project is not affiliated with the Kubernetes project, the CNCF or The Linux Foundation. Kubernetes is a registered trademark of The Linux Foundation.
