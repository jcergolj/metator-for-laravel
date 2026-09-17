# Metator For Laravel

Laravel deployment scaffolding using [Deployer](https://deployer.org/), a
metadata-driven server bootstrap pipeline, and optional web server, DNS, and
queue worker steps.

## Install

```bash
composer require --dev jcergolj/metator-for-laravel
php artisan metator:install
```

The installer stores the selected site ID, SSH target, domain, repository, PHP
version, database, Redis, worker, and scheduler capabilities in a dedicated
`metator.<name>.php` file. Site IDs are immutable and identify remote resources;
filenames, repositories, domains, and checkout names do not. The file contains
no secrets and the command makes no SSH or server changes.

The site ID defaults to the normalized repository name plus the configuration
name, such as `billing-production`. The suggestion is never truncated; if it
does not fit the site ID rules, enter a shorter explicit ID.

The installer also asks for the deployment branch and writes it into the
editable `deploy.php` recipe. The generated baseline does not assume Tailwind,
Importmap, Node, or any other frontend tooling, so an ordinary Laravel
application can deploy without optional asset packages. If an application needs
asset builds, add its project-specific tasks and hook them into the editable
recipe after installation.

Use `--force` only when deliberately replacing an existing site's local
configuration. Provisioning and deployment remain separate explicit commands.

Installs Deployer and generates `deploy.php` and `scripts/`, including a copy of
your application's `.env.example`. The application must provide this file; the
package template is not used as a fallback. The installer publishes the available step
catalogue to `metator/steps/` and lets you select the steps to generate.

The catalogue is also available explicitly through Laravel's publishing command:

```bash
php artisan vendor:publish --tag=metator-steps
```

Run this before `metator:install` if you want to inspect or edit the catalogue
first. If `metator/steps/` does not exist, `metator:install` publishes it
automatically.

## Custom steps

Add custom shell files to `metator/steps/`. The installer displays built-in and
custom steps in the same checkbox list. A step needs six metadata fields and a
function named `step_<id>` where hyphens in the ID become underscores:

```bash
# @id: install-imagemagick
# @title: Install ImageMagick
# @group: none
# @required: false
# @default: false
# @order: 65

step_install_imagemagick() {
    sudo apt-get install -y imagemagick
}
```

Step IDs must start with a lowercase letter and contain only lowercase letters,
numbers, and single hyphens. `@required` and `@default` must be exactly `true`
or `false`; `@order` must be a non-negative integer. IDs that become the same
after hyphens are replaced with underscores are rejected. Functions may use
either `step_example() {` or `function step_example() {` syntax. Steps with
equal order values run in normalized ID order.

The metadata fields mean:

- `@id`: unique step ID. It determines the function name.
- `@title`: text shown in the installer selection list.
- `@group`: mutually exclusive group, or `none` for no group.
- `@required`: required steps cannot be deselected.
- `@default`: whether the step is selected by default.
- `@order`: numeric execution order; lower numbers run first.

Example custom step that runs after the application files are prepared:

```bash
#!/usr/bin/env bash
# @id: install-php-ext-imagick
# @title: Install PHP Imagick extension
# @group: none
# @required: false
# @default: false
# @order: 65

step_install_php_ext_imagick() {
    sudo apt-get update
    sudo apt-get install -y "${PHP_PACKAGE_PREFIX}-imagick"
}
```

The step can use variables and helpers provided by the bootstrap, including
`APP_FOLDER`, `DOMAIN`, `PHP_VERSION`, `PHP_PACKAGE_PREFIX`, `DEPLOY_USER`,
`sudo`, `ok`, `warn`, and `die`.

Custom steps must return a nonzero status when they cannot complete. The
pipeline stops at the first failed selected step, reports the failed operation,
and does not print server readiness. Completed site-owned resources are kept so
the operator can correct the problem and retry.

Custom steps are trusted operator code. They run with the bootstrap's
privileges, and their effects on shared resources are the author's
responsibility. The generated pipeline is uploaded fresh for every remote run;
removed selections are not executed from stale server files. Built-in ownership,
permission, database, repository-access, and handoff steps remain mandatory.

After adding a step, run:

```bash
php artisan metator:install
```

Select the custom step and the other steps you want in the generated pipeline.
The generated `scripts/steps/` directory is the fixed pipeline copied to the
server. It is not intended to be edited during bootstrap.

## Replacing Caddy

The web server is an exclusive step group. To replace Caddy with Nginx, add an
Nginx step to `metator/steps/` and give it the same group with a different ID:

```bash
#!/usr/bin/env bash
# @id: nginx
# @title: Configure Nginx
# @group: web-server
# @required: false
# @default: false
# @order: 70

step_nginx() {
    sudo apt-get install -y nginx
    sudo install -d -m 755 /etc/nginx/sites-enabled
    sudo tee "/etc/nginx/sites-enabled/${APP_NAME}" >/dev/null <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${APP_FOLDER}/current/public;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCKET};
    }
}
EOF
    sudo nginx -t
    sudo systemctl reload nginx
}
```

When prompted, deselect **Configure Caddy** and select **Configure Nginx**.
Only one step in the `web-server` group can be selected.

## Removing Cloudflare

Cloudflare DNS is an optional step. Leave **Configure Cloudflare DNS** unchecked
when installing, and no Cloudflare credentials or DNS API calls will be needed.
The web server step remains independent, so Caddy or Nginx can be used with or
without Cloudflare.

When Cloudflare is selected, installation collects the API token and zone ID
locally and stores them in the untracked `metator.<name>.local.php` companion
file. The remote runner transfers these credentials only for that operation and
removes them from the staging directory afterward. Existing records are used
only when every matching record points to the configured server; conflicts fail
without changing DNS.

Caddy obtains and renews the site's public HTTPS certificate itself. Before
provisioning, create DNS records for the configured domain that point to the
server and allow inbound HTTP and HTTPS traffic. A successful Metator run means
the server infrastructure and Caddy route are ready; it does not mean that
application code has been deployed or that the domain is already serving a
working Laravel response.

## Changing the generated pipeline

The first install creates the selected pipeline. Running the command again
without `--force` preserves existing generated files. To deliberately refresh
the package defaults and choose a new pipeline:

```bash
php artisan metator:install --force
```

The command tracks generated files in `scripts/.metator-manifest.json`. During a
forced regeneration it removes only files listed in that manifest. Other files
in `scripts/steps/` are preserved, so unrelated custom files are not deleted.

The installer derives the application folder and Git SSH alias from the site ID,
then asks for the GitHub repository, server IP, domain, database driver, and deployment steps. Existing generated
files are skipped; use `--force` to regenerate them.

## Bootstrap the server

Metator v1 targets an already-secured Ubuntu 24.04 server with noninteractive
operator administrative access. The supported PHP baseline is PHP 8.4 and 8.5
side by side, with PHP 8.5 as the default for new sites. Basic OS hardening and
operator SSH access are prerequisites, not Metator responsibilities.

The remote Artisan commands upload the generated scripts and run them in their
metadata order. The server must have PHP-FPM, Composer, Git, systemd, and
`sudo` installed, plus noninteractive operator SSH access. The command prompts
stay local; remote steps do not read from SSH stdin.

On the first bootstrap, the shared environment is initialized for production,
including `APP_ENV=production`, `APP_DEBUG=false`, an HTTPS `APP_URL`, and a
generated `APP_KEY`. Existing values and keys are preserved on later runs, while
the selected database settings may be updated. Review `shared/.env` before
confirming the bootstrap prompt.

## Multiple applications

- Give every site a unique site ID. Metator derives the GitHub alias and key
  filename from it under `/home/deployer/.ssh/`.
- Add each app's public key to its repository's GitHub deploy keys. Existing
  keys and unrelated blocks in the shared SSH config are preserved.
- Run one bootstrap at a time; a server-wide lock prevents concurrent updates.
  Cron and Supervisor changes are scoped to the application.
- `.metator-site` records the site ID, repository, PHP version, and database
  selection. Existing unmarked folders and runtime changes are rejected before
  provisioning changes them.
- New environments get unique Redis/cache/Horizon prefixes. For existing apps
  sharing Redis, Metator assigns separate cache and runtime logical databases,
  writes `REDIS_DB` and `REDIS_CACHE_DB`, and sets `CACHE_STORE`,
  `SESSION_DRIVER`, and (for the queues capability) `QUEUE_CONNECTION` to
  Redis. The application's cache, database, session, and Horizon configuration
  must consume these standard environment values; Metator does not modify
  application source configuration.

## Remote workflow

After `metator:install`, choose one site configuration for the remote operation:

```bash
php artisan metator:prepare-server --config=metator.production.php
php artisan metator:provision --config=metator.production.php
```

Metator uploads the exact local `scripts/` directory to a fresh, site-owned
staging directory, streams the remote output, and returns the remote exit
status. The commands use the SSH target from the selected configuration and do
not read from remote stdin. Provisioning does not run Deployer. If SSH stops,
inspect the server before retrying because the remote operation may have
finished.

`prepare-server` checks Ubuntu 24.04 and installs the selected PHP-FPM/CLI
version and required base packages. `provision` reuses that prepared baseline;
it does not install or upgrade shared packages.

### First site

Install one named, non-secret site configuration. The site ID is immutable and
identifies the remote directory and owned resources; it is not derived again
from a repository or checkout name.

```bash
php artisan metator:install
php artisan metator:prepare-server --config=metator.production.php
php artisan metator:provision --config=metator.production.php
vendor/bin/dep deploy production
```

Register the generated read-only GitHub deploy key when the provisioning output
requests it. Preparation is the explicit shared-infrastructure phase. The
provisioning command prepares only the selected site's resources and never runs
the first deployment. Invoke Deployer separately, as shown above, then verify
the configured HTTPS URL, database access, selected scheduler, and selected
queue or Horizon worker.

### Additional sites

Create a second named configuration even when it uses the same repository. Give
it a different site ID and select its own PHP version, database, Redis, worker,
and scheduler capabilities. Run `prepare-server` only when the shared baseline
needs a capability that is not ready; otherwise provision and deploy the new
site directly:

```bash
php artisan metator:install
php artisan metator:provision --config=metator.billing.php
vendor/bin/dep deploy production
```

For the existing-server scenario, keep four deployed sites serving requests and
processing their configured work while adding and separately deploying a fifth.
Confirm that compatible shared packages are reused, unrelated workers are not
restarted, existing domains remain available, and each site's configuration,
credentials, deploy keys, data, and running work are unchanged. Sites sharing a
repository must still have separate site directories and owned resource names.

### Capability choices

Each installation selects capabilities rather than a built-in deployment
workflow. SQLite uses the site's shared database file; local MariaDB creates a
site-owned database, user, and preserved credentials. Redis allocates two
exclusive logical databases per site, one for cache and one for runtime state.
Select no workers, queue workers, or Horizon, and select the scheduler only when
the application uses it. Caddy provides automatic public HTTPS; Cloudflare DNS
is optional and does not replace Caddy. Custom certificates, Nginx, and frontend
build tooling are not v1 prerequisites.

### Retries and changes

An unchanged provisioning rerun verifies existing resources and reports them as
unchanged without rewriting configuration, rotating credentials or keys,
reloading shared services, restarting unrelated workers, or duplicating cron
entries. A failed step returns a nonzero status and the summary does not claim
readiness. Correct the reported problem and rerun after inspecting the server;
successfully created site resources are preserved for recovery.

Changing workers to none stops and removes only that site's managed Supervisor
configuration. Disabling the scheduler removes only that site's managed cron
entry. These changes preserve application files, databases, Redis state,
credentials, keys, and shared services. Re-enable a capability by selecting it
again, provision to stage the owned configuration, and deploy with Deployer to
activate it.

Metator rejects an unmanaged ownership conflict and rejects PHP or database
engine changes during ordinary provisioning. Do not delete the site's data to
work around either error.

To explicitly update application-specific environment values, keep them in a
Git-ignored local dotenv file and select both the site configuration and input:

```bash
php artisan metator:update-env --config=metator.production.php --input=.env.production.local
```

The update preserves Metator-managed identity, runtime, database, and Redis
values, transfers the input without printing secrets, and atomically updates
only the selected site's environment. It does not refresh cached Laravel
configuration or restart workers; run those actions through the normal Deployer
and application lifecycle.

## Troubleshooting

- **Missing shared capability:** Run `metator:prepare-server` for a configuration
  that selects the required capability, wait for it to finish successfully, and
  rerun `metator:provision`.
- **Provisioning failed:** Use the step summary and remote error as the source
  of truth. Inspect the server before retrying; do not assume an interrupted SSH
  connection means that no changes were made.
- **Ownership conflict:** Keep the existing file unchanged and resolve the site
  ID or conflicting managed resource manually. Metator will not adopt an
  unmarked application directory, cron entry, Supervisor file, SSH alias, or
  runtime/database selection.
- **HTTPS is unavailable:** Confirm DNS points to the server and inbound HTTP
  and HTTPS are allowed. Caddy obtains the certificate only after the configured
  domain resolves correctly.
- **Deployment fails after provisioning:** Review `deploy.php`, GitHub deploy-key
  registration, the selected PHP binary, and the application's `.env`. Run
  Deployer separately; provisioning does not deploy application code.

## Resource ownership and removal

Site-owned resources include the site directory and metadata, shared environment,
database or MariaDB credentials, Redis allocations, deploy key and SSH block,
Caddy route, scheduler entry, and worker configuration. Provisioning never
performs a full uninstall or deletes site data. When a site must be removed,
stop its application lifecycle, archive what the operator needs, and remove
these resources manually after checking that no other site uses them. Shared
PHP, MariaDB, Redis, cron, Supervisor, and Caddy services remain in place.

## Deploy

Review `deploy.php` and select one worker mode during installation: no workers,
standard queue workers, or Horizon. The recipe reads the selected site
configuration for its immutable identity, repository, SSH target, deploy path,
PHP executable, database mode, and worker lifecycle. It verifies the provisioned
PHP runtime before any deployment mutation. The generated deploy command already
matches the selected worker mode; no environment override is required:

```bash
vendor/bin/dep deploy production
```
