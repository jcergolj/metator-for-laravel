# Deployer integration proof

## Local workflow evidence

The generated editable recipe uses Deployer 8.0.5 (the resolved version checked
for this proof) and reads the same site configuration used by Metator. A local
task-tree check loads the generated recipe with SQLite and each worker choice
(`none`, `queue`, and `horizon`) and verifies that the deploy workflow contains
runtime verification and release tasks, adds worker lifecycle hooks only when
workers are selected, and does not call Metator preparation or provisioning.
Run it with `php tests/test-deployer-workflow.php` after `composer install`.

The existing shell tests exercise selected custom-step failure propagation,
stop-on-failure, and a successful retry after correcting the failed step. They
also test provisioning input, ownership, and no-op behavior. These are local
tests; they do not establish remote service behavior or remote retry recovery.

## Upstream fit assessment

Inspection of Deployer v8.0.5's `recipe/provision.php` confirms its stock
provision group includes package updates/upgrades, SSH configuration, firewall,
and user changes. These conflict with Metator's explicit shared preparation,
operational-isolation, and existing-operator-access decisions (ADRs 0001,
0016, and 0018). The stock recipe is therefore not a suitable replacement for
Metator's site provisioning pipeline. The generated release recipe does use
Deployer for code deployment and lifecycle hooks, while Metator retains its
site-specific provisioning responsibilities.

## Disposable Ubuntu 24.04 VPS evidence

On 2026-09-25, a disposable Ubuntu 24.04 VPS was provisioned with the generated
configuration for `jcergolj/simpletimer` (`master`, Laravel 13.32.0), site ID
`production-simpletimer`, SQLite, PHP 8.5, scheduler enabled, and no workers or
Redis. The target reported kernel `6.8.0-138-generic`; PHP 8.5.11/FPM came from
Ondřej's PHP PPA and Composer 2.7.1 from Ubuntu packages. The operator connection
used key authentication as root with sudo; Metator created the separate
`deployer` account and configured its SSH key.

Executed outcomes:

- `php artisan metator:prepare-server --config=metator.production.php` completed
  successfully and reported the PHP 8.5/SQLite shared baseline ready.
- Provisioning first reached the selected acceptance step, reported its
  intentional exit status 42, and stopped. After correcting that local custom
  script, rerunning provisioning completed successfully, prepared SQLite,
  configured Caddy and the scheduler, and did not deploy code.
- `vendor/bin/dep deploy production --no-interaction -v` completed twice,
  producing releases 1 and 2. The release cloned the public repository through
  Deployer, installed Composer dependencies, built Tailwind assets, ran Laravel
  migrations, and activated each release separately.
- Caddy and PHP-FPM 8.5 and cron reported active. HTTP returned 308 to HTTPS;
  HTTPS returned 200 with certificate verification result 0.
- A subsequent unchanged `metator:provision` rerun completed. The SQLite file
  remained present and Laravel reported all migrations as applied.

The first live run exposed the PHP SQLite module check's `grep -q`/`pipefail`
false failure; this is fixed in the follow-up branch and covered by
`tests/test-sqlite-database.sh`. The run also showed that launching a remote
editor for environment review fails without a terminal. The follow-up removes
remote interaction and prints local review guidance instead.

## Evidence still required

Ubuntu 26.04 has passed the non-privileged container/PHP test matrix, but has
not been provisioned and deployed on a real VM/VPS. The Ubuntu 24.04 VPS run
covered one site; it did not exercise the fifth-site concurrency and
cross-site-isolation release scenarios. The final evidence-based migration
recommendation and bounded scope for issue #100 are also outstanding. Issue #99
must remain open until the Ubuntu 26.04 real-service run and remaining required
acceptance evidence are recorded. Keep Ubuntu 26.04 support distinct from the
baseline in ADR 0014 until that decision is made.
