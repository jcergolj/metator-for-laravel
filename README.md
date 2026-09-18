# Metator For Laravel

Metator installs deployment scaffolding for Laravel applications. It combines
[Deployer](https://deployer.org/) with a metadata-driven server bootstrap
pipeline.

Metator can prepare:

- PHP-FPM and CLI
- Caddy and optional Cloudflare DNS
- SQLite or site-owned local MariaDB
- Redis cache and runtime databases
- Scheduler and optional queue or Horizon workers
- GitHub deploy-key access

Metator prepares infrastructure. You run Deployer separately to release the
application.

## Requirements

Before installation, provide:

- A Laravel application with `.env.example`
- PHP 8.2 or newer locally
- Composer
- An already secured Ubuntu server
- Noninteractive SSH access with administrative `sudo`
- Git, Composer, PHP-FPM, systemd, and `sudo` on the server

The supported server baseline is Ubuntu 24.04 with PHP 8.4 or 8.5. Basic OS
hardening and operator SSH access are outside Metator's scope.

## Quick Start

Install the package in your Laravel application:

```bash
composer require --dev jcergolj/metator-for-laravel
php artisan metator:install
```

The installer creates:

- `metator.<name>.php`: non-secret site configuration
- `deploy.php`: editable Deployer recipe
- `scripts/`: selected server bootstrap pipeline
- A copy of the application's `.env.example`

Then prepare, provision, and deploy:

```bash
php artisan metator:prepare-server --config=metator.production.php
php artisan metator:provision --config=metator.production.php
vendor/bin/dep deploy production
```

Provisioning does not deploy application code. Register the generated read-only
GitHub deploy key when provisioning requests it.

## Installation Choices

`metator:install` asks for the settings needed by one site:

- Site ID
- Repository and deployment branch
- SSH host and deployment user
- Domain
- PHP version
- SQLite or local MariaDB
- Redis, scheduler, and worker capabilities
- Deployment steps

The site ID is immutable and identifies the remote resources. It is not the
repository name, domain, filename, or local checkout name.

The generated site configuration contains no secrets. Cloudflare credentials,
when needed, are stored separately in an untracked local companion file.

Use `--force` only when deliberately regenerating an existing installation:

```bash
php artisan metator:install --force
```

Forced regeneration removes only files tracked in
`scripts/.metator-manifest.json`. Untracked custom files are preserved.

## Server Workflow

Run the commands in this order:

1. Install the local scaffolding.
2. Prepare the shared server baseline when needed.
3. Provision the selected site.
4. Register the GitHub deploy key.
5. Deploy the application with Deployer.
6. Verify the URL, database, scheduler, and workers selected for the site.

`prepare-server` installs shared packages and capabilities. `provision` creates
only the selected site's resources and reuses the prepared baseline.

The remote commands:

- Upload the exact local `scripts/` directory
- Use a fresh, site-owned staging directory
- Stream remote output locally
- Return the remote exit status
- Do not read from remote stdin

If SSH disconnects, inspect the server before retrying. The remote operation may
have completed.

## Deploying

Review `deploy.php` before the first deployment. It reads the selected site
configuration for the repository, SSH target, deployment path, PHP binary,
database mode, and worker lifecycle.

Deploy with:

```bash
vendor/bin/dep deploy production
```

The generated recipe verifies the provisioned PHP runtime before making release
changes. It supports no workers, queue workers, or Horizon.

### Custom deployment scripts

Add application-specific release work to the editable `deploy.php`. Define a
task, then attach it to a Deployer lifecycle task:

```php
task('deploy:build-assets', function (): void {
    run('cd {{release_path}} && npm ci');
    run('cd {{release_path}} && npm run build');
});

after('deploy:vendors', 'deploy:build-assets');
```

Use:

- `{{release_path}}` for files in the new release
- `{{bin/php}}` for the configured PHP binary
- A hook before `deploy:symlink` for required release files

For Tailwind:

```php
task('deploy:build-tailwind', function (): void {
    run('cd {{release_path}} && {{bin/php}} artisan tailwindcss:download --force');
    run('cd {{release_path}} && {{bin/php}} artisan tailwindcss:build --prod --no-tty');
});

after('deploy:vendors', 'deploy:build-tailwind');
```

If the Tailwind binary is already installed on the server, omit the download
command. A failed task stops deployment before the new release is symlinked.

Verify generated files in the release directory:

```bash
test -f /var/www/<site-id>/releases/<release>/public/.tailwindcss-manifest.json
find /var/www/<site-id>/releases/<release>/public/dist/css -name 'app-*.css' -type f
```

Keep deployment tasks in `deploy.php`. Do not add release commands to the
Metator server bootstrap scripts.

## Custom Server Steps

Custom server steps are shell files in `metator/steps/`. Publish the catalogue
first if you want to inspect or edit the built-in steps:

```bash
php artisan vendor:publish --tag=metator-steps
```

Each custom step needs metadata and a matching function:

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

Metadata rules:

- `@id`: lowercase letters, numbers, and single hyphens
- `@title`: label shown by the installer
- `@group`: exclusive group, or `none`
- `@required`: `true` or `false`
- `@default`: `true` or `false`
- `@order`: non-negative execution order

Available variables and helpers include `APP_FOLDER`, `DOMAIN`, `PHP_VERSION`,
`PHP_PACKAGE_PREFIX`, `sudo`, `ok`, `warn`, and `die`.

Custom steps must return a nonzero status on failure. The pipeline stops and
reports the failed operation. Correct the step and rerun provisioning.

After adding a step:

```bash
php artisan metator:install
```

Select the custom step during installation. The generated `scripts/steps/`
directory is copied to the server and should not be edited there.

## Optional Services

### Web server

Caddy is the default web server and manages public HTTPS. Before provisioning:

- Point DNS to the server
- Allow inbound HTTP and HTTPS
- Ensure the configured domain resolves correctly

To use Nginx instead, add an Nginx step to `metator/steps/` with the
`web-server` group, then select it and deselect **Configure Caddy**. Only one
web-server step may be selected.

### Cloudflare DNS

Cloudflare DNS is optional. Leave **Configure Cloudflare DNS** unchecked when
you do not want API credentials or DNS API calls.

Cloudflare does not replace Caddy. The web server and DNS choices are separate.

### Workers and scheduler

Select only the capabilities used by the application:

- No workers
- Standard queue workers
- Horizon
- Scheduler

Worker and scheduler configuration is scoped to the site. Unrelated sites are
not restarted when one site changes.

## Multiple Sites

Multiple sites may use the same repository. Give each site a unique site ID.

For every site:

- Create a separate `metator.<name>.php`
- Use a unique site ID
- Register its generated GitHub deploy key
- Select its PHP, database, Redis, worker, and scheduler settings
- Provision and deploy separately

Prepare the server again only when a new shared capability is needed. Existing
sites keep their configuration, credentials, data, deploy keys, and running
work.

## Updating Environment Values

Put application-specific production values in a Git-ignored local dotenv file:

```bash
php artisan metator:update-env \
  --config=metator.production.php \
  --input=.env.production.local
```

Metator preserves its managed identity, runtime, database, Redis, and key values.
It does not refresh Laravel's cached configuration or restart workers; use the
normal Deployer and application lifecycle for those actions.

## Retries and Changes

An unchanged provisioning rerun verifies existing resources without:

- Rotating credentials or keys
- Rewriting configuration
- Reloading shared services
- Restarting unrelated workers
- Duplicating cron entries

If provisioning fails, it returns a nonzero status and does not report the site
as ready. Existing site-owned resources are preserved for recovery.

Metator rejects unmanaged ownership conflicts and ordinary PHP or database
engine changes. Resolve those explicitly instead of deleting site data.

## Troubleshooting

### Missing shared capability

Run `metator:prepare-server` for a configuration that selects the capability,
then rerun `metator:provision`.

### Provisioning failed

Use the step summary and remote error as the source of truth. Inspect the server
before retrying.

### Ownership conflict

Keep the existing resource unchanged. Resolve the site ID or conflicting managed
resource manually; Metator will not adopt unmarked resources.

### HTTPS unavailable

Check DNS and inbound HTTP/HTTPS access. Caddy obtains the certificate only when
the configured domain resolves correctly.

### Deployment failed

Review:

- `deploy.php`
- GitHub deploy-key registration
- The selected PHP binary
- The application's `.env`
- Custom deployment tasks

Provisioning and deployment are separate operations, so rerun Deployer after
fixing the deployment issue.

## Resource Ownership

Metator manages site-owned resources including:

- Site directory and metadata
- Shared environment
- Database and MariaDB credentials
- Redis allocations
- GitHub deploy key and SSH block
- Caddy route
- Scheduler entry
- Worker configuration

Metator does not provide a full uninstall command or delete site data. Stop the
site lifecycle, archive required data, confirm no other site uses the resources,
and remove them manually. Shared PHP, MariaDB, Redis, cron, Supervisor, and
Caddy services remain in place.
