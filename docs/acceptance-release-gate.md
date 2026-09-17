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
