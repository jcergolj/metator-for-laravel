# Metator For Laravel

An opinionated deployment setup for Laravel using Deployer, Caddy, Cloudflare, and optional Horizon with Redis.

`php artisan metator:install` is a wrapper around the usual Deployer setup. It adds `deploy.php` and the extra `scripts/` helpers for server setup.

## Install

```bash
composer require --dev jcergolj/metator-for-laravel
php artisan metator:install
```

The install command asks for the deployment settings and which optional server
features to include. It renders those choices into the bootstrap scripts and
copies only the selected step scripts. The Git SSH deployer name is used for
both the GitHub SSH alias and the private key filename.

Installing this package also installs `deployer/deployer`.

## Installer Prompts

`php artisan metator:install` asks for:

- Application folder, defaulting to `/var/www/<project-name>`
- GitHub repository, defaulting to `jcergolj/<project-name>`
- Production server IPv4 address
- Git SSH deployer name, defaulting to `deployer-github-<project-name>`
- Production domain
- Database driver: SQLite or MySQL
- Whether to configure SSH login for the `deployer` user
- Whether to include Cloudflare DNS configuration
- Whether to include the Laravel scheduler
- Whether to include queue workers
- Whether to use Horizon when queue workers are enabled

The answers are rendered into `scripts/server-bootstrap.sh` and determine which
optional step scripts are copied. The bootstrap still asks for values that must
not be stored in generated files, such as Cloudflare credentials and MySQL
credentials. It also pauses when a shared environment or Supervisor file
changes so it can be reviewed.

## What it adds

- Deployer as a dependency
- `deploy.php`
- `scripts/server-bootstrap.sh`
- `scripts/.env.example` copied from the application
- `scripts/lib/common.sh`
- the required and selected optional scripts in `scripts/steps/`

## What the scripts do

`./scripts/server-bootstrap.sh` uses the settings selected during install. Run
it on the target server as the first-time setup for that application. It checks
the server, configures the selected services, keeps going if a step fails, and
prints a final summary. It can:

- create the `deployer` user if it does not exist
- add your public SSH key to `authorized_keys` for `deployer` login
- create an app-specific GitHub deploy key and configure its SSH alias for the `deployer` user
- optionally create a Cloudflare DNS A record for the domain using a Cloudflare zone ID
- create the shared Laravel `.env` with every variable from `.env.example` and wait for review when it changes
- merge missing variables from `.env.example` into the shared `.env`
- configure SQLite or MySQL connection values when required
- create the shared SQLite database file when SQLite is used
- configure shared file permissions
- add `import /etc/caddy/sites-enabled/*.caddy` to `/etc/caddy/Caddyfile` when missing
- create and validate the Laravel app Caddy site file in `/etc/caddy/sites-enabled/`
- add the Laravel scheduler cron job
- configure Supervisor for `queue:work` or Horizon
- install Redis when Horizon is selected
- use the latest detected PHP-FPM version when installing PHP database extensions
- print the next deployment steps for `deploy.php`

Each application has its own GitHub key and SSH alias. The key is created only
when it does not already exist, and the public key must be added to that
repository's GitHub deploy keys. Applications on the same server use the
shared `/home/deployer/.ssh/config`, with one `Host` block per application
alias; do not replace that file when adding another site.

Typical generated or updated files during bootstrap:

- shared Laravel environment: `/var/www/<app-name>/shared/.env`
- Caddy site config: `/etc/caddy/sites-enabled/<app-name>.caddy`
- Supervisor worker config: `/etc/supervisor/conf.d/<app-name>-worker.conf`
- GitHub private key: `/home/deployer/.ssh/<git-ssh-deployer-name>`
- GitHub SSH alias: `<git-ssh-deployer-name>`

## Notes

- Without `--force`, the installer skips files that already exist. Use
  `php artisan metator:install --force` to overwrite generated files.
- Review `deploy.php` after install.
- Add the newly generated public key to that repository's GitHub deploy keys. Deploy keys cannot be reused across repositories.
- Existing keys from older versions are not overwritten; bootstrap creates the new app-specific key alongside them.
- Ensure the latest detected `phpX.Y-fpm` service is installed and running before bootstrap, because the script uses that version for the FPM socket and PHP database extensions.
- Ensure Caddy is installed before bootstrap, because the script updates `/etc/caddy/Caddyfile`, validates the config, and reloads the service.

## Fresh Server Bootstrap

For a fresh server, copy the generated `scripts/` directory first:

```bash
scp -r scripts user@SERVER_IP:/tmp/
ssh user@SERVER_IP
cd /tmp/scripts
bash server-bootstrap.sh
```

For an existing server, copy the generated `scripts/` directory to a temporary
location and run the bootstrap there as well. The script uses the embedded
application settings, so use the scripts generated for the application being
configured.

## Deploy

After bootstrap completes, review `deploy.php` and deploy the app with
Deployer:

```bash
vendor/bin/dep deploy production
```

Deployer: https://deployer.org/
