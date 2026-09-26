# Ubuntu Release Gate

The local shell suite validates generated scripts and mocked service boundaries.
The v1 release gate must additionally run against disposable Ubuntu 24.04 and
Ubuntu 26.04 targets with real PHP, Composer, Git, systemd, Caddy, MariaDB,
Redis, cron, and Supervisor services.

`tests/acceptance/run-release-gate.sh` supplies the reproducible lifecycle
boundary. A provider command creates one disposable target and prints these
assignments, one per line:

```text
host=203.0.113.10
user=ubuntu
identity=/path/to/temporary-key
target_id=unique-provider-id
```

Set `METATOR_ACCEPTANCE_CREATE`, `METATOR_ACCEPTANCE_SCENARIO`, and
`METATOR_ACCEPTANCE_DESTROY` to executable commands. Set
`METATOR_ACCEPTANCE_UBUNTU_RELEASES` to a whitespace-separated list of
releases, defaulting to `24.04 26.04`. For each release the runner sets
`METATOR_ACCEPTANCE_UBUNTU_RELEASE` before invoking the provider, verifies the
Ubuntu version and required baseline over SSH, records target metadata in a
release-specific evidence directory, runs the scenario, and invokes cleanup
even when a check fails. The scenario must create Laravel applications, run
`metator:prepare-server` and `metator:provision`, and invoke Deployer separately,
cover the supported PHP, database, Redis, worker,
scheduler, retry, no-op, fifth-site, and isolation cases, and write
command/results evidence to `METATOR_ACCEPTANCE_EVIDENCE_DIR`.

Provider credentials and disposable infrastructure are intentionally outside
the normal pull-request CI job. A release run must retain the provider, image,
package/PHP versions, applications, commands, and results with the evidence.

## Hetzner Redis isolation run

The focused Redis gate uses `tests/acceptance/run-hetzner-redis-gate.sh`. It
creates a new Ubuntu 24.04 `cx23` VM in `nbg1`, creates an isolated local SSH
home, provisions two `jcergolj/simpletimer` sites with separate Redis cache and
runtime databases, and deletes the VM and temporary GitHub deploy keys after
the run. Its SSH/scp wrappers use only the temporary key and temporary
`known_hosts`, leaving the operator's SSH configuration untouched. It does not
reimage or modify an existing server. The server requires
`HCLOUD_TOKEN`; GitHub deploy-key registration requires `GH_TOKEN` or an active
`gh auth` session with permission to administer deploy keys for the fixture
repository. Evidence defaults to a retained temporary directory and its path is
printed by the runner.

Run it with:

```bash
tests/acceptance/run-hetzner-redis-gate.sh
```

The scenario clears the Horizon site's Laravel cache, checks that the queue
site's cache remains, verifies one delayed Laravel queue job and a Redis-backed
Laravel session survive for both sites, and confirms Horizon remains running.
An acceptance-only Deployer hook installs Horizon into the disposable release;
the fixture repository itself is not modified. It then performs another
queue-site Deployer release and verifies that the Horizon worker PID is
unchanged. The focused wrapper defaults to Ubuntu 24.04; override
`METATOR_ACCEPTANCE_UBUNTU_RELEASES` only when the selected provider supports
the requested release.
