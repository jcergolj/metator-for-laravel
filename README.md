# Metator For Laravel

Installs Deployer scaffolding into an existing Laravel app.

## Install

```bash
composer require --dev jcergolj/metator-for-laravel
php artisan metator:install
```

## What it adds

- `deploy.php`
- `scripts/setup.sh`
- `scripts/lib/*`
- `scripts/steps/*`

## Notes

- Use `php artisan metator:install --force` to overwrite existing files.
- Review `deploy.php` after install.
- Run `./scripts/setup.sh` on the server.
