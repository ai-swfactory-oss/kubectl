# @ai-swfactory-oss/kubectl

[kubectl](https://kubernetes.io/docs/reference/kubectl/), the Kubernetes command-line tool, as an npm package that runs the **native upstream binary** for your platform (no download at install time, no install scripts).

Platforms: `linux-x64`, `linux-arm64`, `darwin-x64`, `darwin-arm64`. The binary comes from the matching optional dependency `@ai-swfactory-oss/kubectl-<platform>-<arch>`: the unmodified `kubectl` from dl.k8s.io, verified against the sha256 and sha512 that dl.k8s.io publishes for it.

## Install

The packages are on GitHub Packages. Point the scope at it (in your project's `.npmrc`):

```
@ai-swfactory-oss:registry=https://npm.pkg.github.com
```

GitHub Packages requires a token even for public packages: a classic personal access token with `read:packages`, in your user `~/.npmrc` (never commit it):

```
//npm.pkg.github.com/:_authToken=<token>
```

In GitHub Actions, `actions/setup-node` with `registry-url: https://npm.pkg.github.com` and `NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` does this (the workflow needs `packages: read`).

```sh
npm install --save-dev @ai-swfactory-oss/kubectl
npx kubectl version --client
```

## Use

From Node, spawn the binary directly:

```js
const { binaryPath, upstreamVersion } = require('@ai-swfactory-oss/kubectl');
// binaryPath(): absolute path to the native kubectl binary for this os and cpu
// upstreamVersion: the kubectl version, e.g. "1.37.1"
```

`binaryPath()` throws `UnsupportedPlatformError` (with `platform` and `arch`) when no binary is published for this os and cpu, and `PlatformPackageMissingError` when one is but its package was not installed (for example with `--omit=optional`).

## Verify

Every published tarball and binary has a GitHub build-provenance attestation:

```sh
gh attestation verify node_modules/@ai-swfactory-oss/kubectl-linux-x64/bin/kubectl \
  --repo ai-swfactory-oss/kubectl
```

The binary itself is upstream's release binary, unmodified, its sha256 and sha512 pinned (see `NOTICE` in the platform package). Details: https://github.com/ai-swfactory-oss/kubectl#verify-what-you-installed

## Versions

The package version equals the kubectl version. A rare re-pack of the same kubectl release (packaging fix only) is published as `<version>-r.<n>` with the `latest` dist-tag.

## License

Apache-2.0, the license of kubectl. See `LICENSE` and `NOTICE`.
