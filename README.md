# Metator For Laravel

Laravel deployment scaffolding using [Deployer](https://deployer.org/), Caddy,
Cloudflare, and optional queue workers or Horizon.

## Install

```bash
composer require --dev jcergolj/metator-for-laravel
php artisan metator:install
```

Installs Deployer and generates `deploy.php` and `scripts/`, including a copy of
your application's `.env.example`.

The installer asks for the application folder, GitHub repository, server IP,
domain, Git SSH name, database driver, and optional SSH login, DNS, scheduler,
and queue setup. Existing files are skipped; use `--force` to regenerate them.

## Bootstrap the server

Have PHP-FPM, Composer, Git, Caddy, and the Cloudflare certificate/key installed.
Bootstrap uses the latest detected PHP-FPM service and requires `sudo` access.

Copy scripts to `/var/init-scripts/<owner>/<repo>`. These commands create the
directory if missing and copy all script contents, including `.env.example`:

```bash
ssh -t user@SERVER_IP 'sudo install -d -m 755 -o "$(id -un)" -g "$(id -gn)" /var/init-scripts/OWNER/REPO'
scp -r scripts/. user@SERVER_IP:/var/init-scripts/OWNER/REPO/
ssh user@SERVER_IP
cd /var/init-scripts/OWNER/REPO
bash server-bootstrap.sh
```

Replace `OWNER/REPO` with your GitHub repository, e.g. `acme/billing`. Use the
same commands to update an existing server's scripts.

Bootstrap configures the deployer user, GitHub access, shared `.env`, database
driver, permissions, Caddy, and selected optional services. It prompts for
credentials and configuration reviews, then prints a step summary.

## Multiple applications

- Give every app a unique folder and Git SSH name. The SSH name is both the
  GitHub alias and key filename under `/home/deployer/.ssh/`.
- Add each app's public key to its repository's GitHub deploy keys. Existing
  keys and unrelated blocks in the shared SSH config are preserved.
- Run one bootstrap at a time; a server-wide lock prevents concurrent updates.
  Cron and Supervisor changes are scoped to the application.
- `.metator-repository` prevents later reuse of an app folder by another
  repository. Check existing unmarked folders before their first bootstrap.
- New environments get unique Redis/cache/Horizon prefixes. For existing apps
  sharing Redis, check `REDIS_PREFIX`, `CACHE_PREFIX`, and `HORIZON_PREFIX` are
  distinct and used by the app's configuration.

## Deploy

Review `deploy.php`, including any queue restart hooks, then run locally:

```bash
vendor/bin/dep deploy production
```
