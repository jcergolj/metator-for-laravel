# Shared runtime permissions

Metator provisions the selected site's `shared/storage`, `shared/bootstrap/cache`
and, when present, `shared/database` with group `www-data`, setgid directories
(`2770`), files (`0660`), and default directory ACLs:

```text
default:user::rwx
default:group::rwx
default:other::---
```

Setgid alone preserves the group but does not preserve group-write access under
umask `0022`. The default ACL supplies that access for normal file creation
(`0666`) and directory creation (`0777`), including nested storage and recreated
logs. Explicitly restrictive creation modes or a later application/logrotate
`chmod` can still revoke access; this is not a way to override deliberate mode
changes. No global umask or PHP-FPM configuration is changed.

`metator:prepare-server` installs Ubuntu's `acl` package only when missing (or
repairs missing ACL commands). Existing installations need regenerated scripts,
shared preparation if ACL support is absent, and provisioning of the selected
site. Deployer remains a separate operation. Newly generated recipes skip
Deployer's permission mutation because provisioning owns this policy; merge that
setting into a customized recipe when upgrading.

Provisioning repairs inaccessible existing runtime resources without changing
contents, preserves ownership by either the deployment user or `www-data`, and
normalizes other owners to the deployment user. It reconciles ACLs and modes only
when different. It does not recursively change the deployment home or unrelated
shared files. `shared/.env` remains deployment-owned, mode `0640`, readable but
not writable by `www-data`. Neither `shared/` nor `shared/bootstrap/` receives a
default ACL, so secrets outside the runtime trees do not inherit runtime access.

Managed directory ancestors and `.env` must not be symlinks. Traversal inside
runtime trees does not follow symlinks or descend onto other filesystems. This
supports operational isolation, not containment of a compromised runtime racing
an administrator's provisioning run.

## Readiness and reruns

Existing runtime files and directories are checked as both actual identities.
When resources change, unique temporary probe directories exercise nested
creation and cross-identity append in both directions under umask `0022`. Cleanup
only removes those probes; it never opens application logs for writing.

Matching reruns verify ACLs and identity access without chmod/chown/setfacl or
creating probes in runtime directories. This avoids changing existing directory
modification/change timestamps just to demonstrate a successful no-op. Failed
identity checks still stop provisioning with a nonzero status.

## Verification for #113

Run the regression tests with:

```bash
TMPDIR=/tmp/opencode bash tests/test-runtime-permissions.sh
bash tests/test-permissions.sh
```

The first test performs real Linux DAC/ACL checks with distinct identities. It
runs as root when available, otherwise uses an unprivileged user/mount namespace
with subordinate UID/GID mappings (`unshare`, `newuidmap`, `newgidmap`). Its NSS
fixtures are mounted privately; it does not create host accounts. The second
test checks reconciliation using the current identity and mocked identity lookup;
it is not evidence of cross-identity permission enforcement.

On the development Linux host, the first command reproduced the original bug
before the fix: `Permission denied` appending to a runtime-created log. After the
fix it passed creation/appending in both directions, nested directories, log
recreation, existing-log repair without content loss, ownership preservation,
protected `.env`, unchanged rerun metadata/ACLs/content, probe cleanup, and another
site's preservation through interior and root symlinks. Injected identity/probe
failures additionally verify nonzero status and failure cleanup; these injected
checks are not real service failures.

The clean #113 release snapshot (excluding unrelated local edits) also passed
all 27 `tests/*.sh` scripts, all four `tests/*.php` scripts, ShellCheck over
`tests/` and `stubs/scripts/`, PHP syntax checks over `src/`, and
`composer validate --no-check-publish`.

**Not verified:** disposable Ubuntu 24.04 provisioning followed by a separate
Deployer release, Laravel Artisan commands and a real PHP-FPM request. The
development host has no configured disposable provider credentials. Linux
namespace checks are not a substitute for that release-gate handoff. Record the
Ubuntu image, PHP/service versions, application, commands and results when that
integration run is available; see [the release gate](acceptance-release-gate.md).
