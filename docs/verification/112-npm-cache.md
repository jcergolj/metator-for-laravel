# Issue #112: npm cache verification

Date: 2026-10-24.

## Automated regression checks

All 29 top-level shell tests and four PHP tests passed, along with ShellCheck,
PHP syntax checks, Composer validation, and `git diff --check`.

`tests/test-npm-cache.sh` uses real npm and filesystem permissions in a user
namespace locally (or elevated execution in CI). Its privilege-switch helper
substitutes `setpriv` for sudo; npm and filesystem operations are not mocked.
It reproduces `EACCES` for a missing cache under a root-owned, non-writable home,
then checks provisioning, cache use, read-only content blobs, unchanged reruns,
another site, inaccessible data, and refusal to follow cache symlinks.

The PHP tests load the generated recipe with Deployer and check the Node-enabled
and disabled configuration, plus installation's Node-step/configuration handoff.

## Actual Ubuntu userspace and Deployer build

Executed `tests/acceptance/scenarios/npm-cache-build.sh` twice in a disposable
Ubuntu root filesystem, using a user/mount namespace and chroot:

- Image: Ubuntu Base 24.04.4 LTS, amd64,
  `https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.4-base-amd64.tar.gz`.
- Image SHA-256: `c1e67ef7b17a6300e136118bd1dc04725009cb376c1aad10abcf8cd453628d58`.
- First run: Ubuntu-packaged Node.js 18.19.1 and npm 9.2.0.
- Second run: Node.js 26.8.2 binary and registry-distributed npm 11.19.1,
  matching the reported runtime versions (not a NodeSource installation test).
- Deployer: Composer package 8.0.5 (`dep --version` reports `master`), with
  PHP CLI 8.3.6 and Symfony 7.4 dependencies for this isolated build runner.
- Build fixture: Vite 5.4.21, a package lock, HTML entry point, and JavaScript.

On a disposable Ubuntu environment with these tools and Composer dependencies
already installed, run as root:

```bash
METATOR_ACCEPTANCE_DISPOSABLE=true \
  bash tests/acceptance/scenarios/npm-cache-build.sh
```

Both runs passed. The script creates a test deployment identity with a root-owned
`0755` home, invokes the real site claim and Node provisioning step, and runs the
generated recipe's environment through a Deployer localhost task as that identity:

```text
test "$(npm config get cache)" = "/var/www/<site-id>/shared/.npm"
npm ci --include=dev --no-audit --no-fund
npm run build
vite v5.4.21 building for production...
dist/index.html
dist/assets/index-Dm87bFiW.js
PASS real npm ci/Vite build, root-owned home, unchanged cache rerun, second site, and failed readiness
```

The home remains root-owned and has no `.npm`. Cached entries' contents, modes,
owners, and timestamps survive provisioning reruns and second-site addition.
Readiness creates and removes only its unique probe directory; it does not run
`npm cache verify`, which can prune or rewrite cached data. Making the existing
cache inaccessible produces a clear nonzero readiness failure.

## Limits

This is real Ubuntu userspace/npm/Vite/Deployer execution, not a VPS/VM run or the
complete `docs/v1-acceptance.md` gate. It directly exercises the Node provisioning
step and generated recipe handoff, not Artisan remote staging, SSH deployment,
Git checkout, a Laravel release, PHP 8.4/8.5-FPM, or live service/worker isolation.
Those full-server acceptance requirements remain unverified by this evidence.
