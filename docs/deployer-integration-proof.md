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

## Disposable Ubuntu 26.04 VPS evidence (MariaDB)

On 2026-09-25, the disposable Hetzner server (ID `167422114`,
`188.245.29.40`) was rebuilt to Ubuntu 26.04.1 LTS, kernel
`7.0.0-30-generic`. The selected `jcergolj/simpletimer` `master` revision was
`531ff54fa2f7083532fc4e28aaba4e91385de463` (Laravel 13.32.0). The generated
site ID was `production-simpletimer`, using PHP 8.5.4 CLI/FPM, MariaDB
11.8.6-MariaDB-5ubuntu0.1, Caddy 2.6.2, Composer 2.9.5, and Deployer 8.0.5.
The domain `simpletimer.188.245.29.40.sslip.io` resolved to the server.

Executed commands and outcomes:

- `php artisan metator:prepare-server --config=metator.production.php` installed
  and verified PHP 8.5, MariaDB, Caddy, cron, and the Composer/Git baseline. It
  created the separate `deployer` account and reported success.
- `php artisan metator:provision --config=metator.production.php` initially
  exposed a GitHub host-key check issue: `ssh-keyscan` emitted a banner comment
  alongside the pinned ED25519 key, while the script compared all stdout
  literally. The key itself matched GitHub's published fingerprint. The check
  now filters for unique `github.com ssh-ed25519` records; the collision test
  fixture includes an SSH banner to cover this case. The repository shell test
  suite passed after the fix.
- After registering a temporary read-only GitHub deploy key, provisioning
  created the site environment and site-scoped MariaDB database/user, configured
  Caddy and the scheduler, then intentionally stopped at the selected custom
  step with exit status `42`. After correcting that local custom step,
  provisioning was rerun successfully. It verified GitHub access and retained
  the existing site-owned database and credentials.
- `php artisan metator:update-env --config=metator.production.php --input=.env.production.local`
  set SimpleTimer's main domain for this test.
- `vendor/bin/dep deploy production --no-interaction -v` ran separately and
  deployed release 1. It installed Composer dependencies, built Tailwind assets,
  applied all ten Laravel migrations to MariaDB, and activated the release.
  A Laravel PDO query returned the MariaDB server version. Caddy and PHP-FPM,
  MariaDB, and cron were active. HTTP returned 308 to HTTPS; HTTPS returned 200
  with certificate verification result 0.
- A subsequent unchanged `metator:provision` rerun succeeded. Before/after
  snapshots showed identical hashes for the shared `.env`, site metadata,
  operator/deployment SSH files, Caddy configuration, and scheduler file;
  MariaDB database/user counts remained one, and service active-enter timestamps
  were unchanged.
- The temporary GitHub deploy key and operator SSH key were removed after the
  run. The deployed site remains on the disposable server for inspection.

## Ubuntu 26.04 four-sites-to-fifth live evidence

On 2026-09-25, the same Ubuntu 26.04.1 Hetzner server was used for the existing
`production-simpletimer` site plus four `jcergolj/simpletimer` sites sharing
commit `531ff54fa2f7083532fc4e28aaba4e91385de463`:

| Site ID | Database | Worker | PHP |
| --- | --- | --- | --- |
| `production-simpletimer` | MariaDB | none | 8.5 |
| `site2-simpletimer` | SQLite | queue | 8.5 |
| `site3-simpletimer` | MariaDB | none | 8.5 |
| `site4-simpletimer` | SQLite | none | 8.5 |
| `site5-simpletimer` | MariaDB | none | 8.5 |

Each site used its own `sslip.io` domain, site ID, configuration, environment,
database resources, and scheduler entry. Sites 2–5 each used a separate
read-only GitHub deploy key. Each of sites 2–5 was explicitly prepared and
provisioned with Artisan, then separately deployed with its generated Deployer
recipe. All five HTTPS URLs returned 200
with certificate verification result 0; all ten migrations were applied in the
new site databases. `visudo -cf` accepted the generated site-2 worker policy.
Supervisor reported `site2-simpletimer-worker` RUNNING (PID 33482).

During site-5 provisioning and its separate Deployer deployment, the four
existing sites were probed over HTTPS every two seconds for 40 cycles per
operation. Every probe returned 200 with certificate verification; the site-2
queue worker remained RUNNING with the same PID. Before/after snapshots matched
for the existing sites' `.env` files, metadata, Caddy site routes, scheduler
entries, site-2 worker configuration and sudo policy, deployer authorized keys,
and site-2–4 GitHub private keys. MariaDB schemas for sites 1 and 3 remained
present, and explicit data fixtures in site 1's MariaDB and site 2's SQLite
database remained present. Shared-service active-enter timestamps and package
versions did not change. SQLite database-file hashes changed during the live
background-work interval; the fixture rows and all recorded migrations
remained present, so byte-for-byte database-file equality was not observed.

The first attempt to prepare site 2 with PHP 8.4 failed because the generated
`ppa:ondrej/php` source returned 404 for Ubuntu `resolute` (26.04); its response
directs Resolute users to `packages.sury.org/php`. That invalid PPA source was
removed and `apt-get update` then succeeded. Site 2 was reconfigured to PHP 8.5
for the five-site run; PHP 8.4/8.5 coexistence was verified separately below.

The queue-worker setup also exposed that Ubuntu 26.04's `sudoers` rejects the
generated `supervisorctl group:*` wildcard arguments. The rule and generated
Deployer recipe now target the exact `group:process` instance, escaping the
colon in the sudoers file. `visudo` accepted the final rule, Deployer activated
and verified the worker, and the complete `tests/*.sh` suite passed. These
source/test changes are local and uncommitted.

## Ubuntu 26.04 PHP 8.4/8.5 co-location and site-add evidence

On the same Ubuntu 26.04.1 server, site `site6-simpletimer` was installed with
PHP 8.4.26 from `packages.sury.org/php` alongside the existing PHP 8.5.4 runtime
from Ubuntu. Metator installed the Sury archive keyring, added a dedicated
`metator-php-sury.list` source for `resolute`, and installed PHP 8.4 CLI/FPM and
extensions. `php-fpm8.4 -t` and `php-fpm8.5 -t` both passed, and both FPM
services were active.

`metator:prepare-server` and `metator:provision` completed for site 6. The first
Deployer attempt failed because the PHP 8.4 package set omitted `intl`, which
Composer needs (`Normalizer` was unavailable). PHP preparation now includes
`php${PHP_VERSION}-intl`; after installing it, a Deployer retry succeeded as
release 2, applied all ten migrations using PHP 8.4, and activated the site.
This exercised recovery from the failed first release.

To exercise a mixed-version add while current sites remained live, site
`site7-simpletimer` was then prepared/provisioned/deployed on PHP 8.5 while six
existing sites included the PHP 8.4 site 6. The six existing HTTPS endpoints
were probed every two seconds for 40 cycles during both provisioning and
deployment; every probe returned 200. The site-2 queue worker remained RUNNING
throughout. All seven site URLs subsequently returned HTTPS 200 with certificate
verification result 0.

During an early PHP 8.4 attempt, the system reported the `curl` package installed
although its executable was missing. Reinstalling `curl` upgraded `libcurl` and
restarted PHP 8.5-FPM and Supervisor, which stopped the site-2 worker; I restarted
it and verified recovery. Afterward, the successful Sury installation and
mixed-version site-add runs were monitored separately; the worker remained
RUNNING throughout those runs. The prerequisite step now detects missing command
binaries even when dpkg reports their packages as installed, repairs those
packages, and selects Sury only for Ubuntu 26.04/PHP 8.4. Its tests verify source
selection, keyring setup, and refusal to overwrite a conflicting source. The
complete `tests/*.sh` suite passes.

## Ubuntu 24.04 site-scoped Redis operation evidence

On 2026-09-26, `tests/acceptance/run-hetzner-redis-gate.sh` created a new
disposable Hetzner `cx23` VM in `nbg1` running Ubuntu 24.04.4 LTS. The operator
used a temporary SSH key with a temporary `known_hosts`; the acceptance runner
deleted the VM, Hetzner SSH key, local private key, and temporary GitHub deploy
keys after the run. No existing VM was reimaged or changed.

The test used `jcergolj/simpletimer` master revision
`531ff54fa2f7083532fc4e28aaba4e91385de463` (Laravel 13.32.0), PHP 8.5.11, Redis
7.0.15, and Deployer 8.0.5. Two independently provisioned sites shared that
repository and server:

| Site ID | Cache DB | Runtime DB | Worker |
| --- | ---: | ---: | --- |
| `redis-one` | 1 | 2 | Queue |
| `redis-two` | 3 | 4 | Queue |

After separately provisioning and deploying both sites, the test inserted
distinct entries through Laravel's Redis cache store, queued one delayed Laravel
closure job per site, created and reread one Redis-backed Laravel session per
site, and wrote a Horizon-state marker into each runtime database. Running
`php artisan cache:clear` for `redis-one` removed its cache entry; `redis-two`'s
cache entry remained. Both queue sizes remained 1, both sessions retained their
values, and both runtime-database markers remained intact. The Horizon marker is
a direct Redis sentinel; this scenario did not run the Horizon package/daemon.

The scenario then ran a separate Deployer release for `redis-one`. Its queue
worker changed PID from 20527 to 21481; `redis-two` remained RUNNING with PID
19854. Both site URLs returned HTTPS 200 before the state checks. The detailed
run summary is at `/tmp/metator-redis-evidence.qlHjrD/ubuntu-24.04/redis-isolation.txt`;
`target.txt` records the Ubuntu image, PHP, and systemd versions.

## Recommendation for the follow-up

Deployer 8.0.5 is a good fit for the separate release workflow: its Laravel
recipe supplies release setup, Git update, dependency installation, migrations,
cache, symlink activation, and cleanup. The generated Metator recipe adds runtime
verification, Tailwind build, and selected worker lifecycle hooks. This
integration removes no existing Metator provisioning execution path; Deployer's
stock provision tasks conflict with the verified ownership, no-op, SSH,
database-grant, and service-isolation behavior.

Recommendation: keep the selective integration and do not port the stock
provision recipe or retire `RemoteScriptRunner`/selected bootstrap steps as part
of #100. Refine #100 into a bounded follow-up for the generated deployment
interface, migration instructions, and capability-specific checks. Remove
provisioning code only in later slices that identify and verify a specific
duplicate while preserving the existing ADR guarantees. The live Redis cache,
queue, session, and worker-isolation checks are recorded above; the Horizon
marker was not a live Horizon process test. Keep Ubuntu 26.04 distinct from the
support baseline in ADR 0014 until that decision is made.
