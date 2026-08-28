# Metator For Laravel

An opinionated deployment setup for Laravel using Deployer, Caddy, Cloudflare, and optional Horizon with Redis.

`php artisan metator:install` is a wrapper around the usual Deployer setup. It adds `deploy.php` and the extra `scripts/` helpers for server setup.

## Install

```bash
composer require --dev jcergolj/metator-for-laravel
php artisan metator:install
```

Installing this package also installs `deployer/deployer`.

## What it adds

- Deployer as a dependency
- `deploy.php`
- `scripts/server-bootstrap.sh`
- `scripts/lib/*`
- `scripts/steps/*`

## What the scripts do

`./scripts/server-bootstrap.sh` is an interactive server setup script. It can:

- create the `deployer` user if it does not exist
- add your public SSH key to `authorized_keys` for `deployer` login
- create a GitHub deploy key for the server and configure the SSH alias
- optionally create a Cloudflare DNS A record for the domain
- create the shared Laravel `.env`
- configure SQLite or MySQL connection values
- create the shared SQLite database file when SQLite is used
- configure shared file permissions
- configure Caddy for the Laravel app
- add the Laravel scheduler cron job
- configure Supervisor for `queue:work` or Horizon
- install Redis when Horizon is selected
- print the next deployment steps for `deploy.php`

## Notes

- Use `php artisan metator:install --force` to overwrite existing files.
- Review `deploy.php` after install.

## Fresh Server Bootstrap

For a fresh server, copy the generated `scripts/` directory first:

```bash
scp -r scripts user@SERVER_IP:/tmp/
ssh user@SERVER_IP
cd /tmp/scripts
bash server-bootstrap.sh
```
