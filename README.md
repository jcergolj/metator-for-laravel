# Metator For Laravel

Laravel deployment scaffolding using [Deployer](https://deployer.org/), a
metadata-driven server bootstrap pipeline, and optional web server, DNS, and
queue worker steps.

## Install

```bash
composer require --dev jcergolj/metator-for-laravel
php artisan metator:install
```

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

The installer asks for the application folder, GitHub repository, server IP,
domain, Git SSH name, database driver, and deployment steps. Existing generated
files are skipped; use `--force` to regenerate them.

## Bootstrap the server

Have PHP-FPM, Composer, Git, and the software required by the selected steps
installed. Bootstrap uses the latest detected PHP-FPM service and requires
`sudo` access.

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

Bootstrap executes the selected steps in their metadata order. It prompts for
credentials and configuration reviews, then prints a step summary.

On the first bootstrap, the shared environment is initialized for production,
including `APP_ENV=production`, `APP_DEBUG=false`, an HTTPS `APP_URL`, and a
generated `APP_KEY`. Existing values and keys are preserved on later runs, while
the selected database settings may be updated. Review `shared/.env` before
confirming the bootstrap prompt.

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

Review `deploy.php` and select the configured worker type. Horizon is the
default; use `WORKER_TYPE=queue` for standard queue workers:

```bash
WORKER_TYPE=queue \
vendor/bin/dep deploy production
```
