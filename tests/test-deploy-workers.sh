#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_file="$ROOT_DIR/stubs/deploy.php.stub"

php -l "$deploy_file" >/dev/null

activate_line="$(grep -n "task('deploy:activate-workers'" "$deploy_file" | cut -d: -f1)"
symlink_line="$(grep -n "after('deploy:symlink', 'deploy:activate-workers')" "$deploy_file" | cut -d: -f1)"
restart_line="$(grep -n "after('deploy:activate-workers', 'deploy:restart-workers')" "$deploy_file" | cut -d: -f1)"
verify_line="$(grep -n "after('deploy:restart-workers', 'deploy:verify-workers')" "$deploy_file" | cut -d: -f1)"

[[ -n "$activate_line" && -n "$symlink_line" && -n "$restart_line" && -n "$verify_line" ]]
(( symlink_line > activate_line ))
(( restart_line > symlink_line ))
(( verify_line > restart_line ))

grep -Fq "run('sudo supervisorctl update {{application}}-worker');" "$deploy_file"
grep -Fq "run('sudo supervisorctl restart {{application}}-worker:*');" "$deploy_file"
if grep -Fq "run('sudo supervisorctl update');" "$deploy_file"; then exit 1; fi

# Exercise the actual generated process pattern with versioned PHP binaries.
pattern="$(sed -n "s/.*pgrep -af '\(.*\)'.*/\1/p" "$deploy_file")"
pattern="${pattern//\{\{deploy_path\}\}/\/var\/www\/billing}"
for worker in horizon queue:work; do
    worker_pattern="${pattern//\{\$workerCommand\}/$worker}"
    for php in php php8.4 php8.5; do
        printf '/usr/bin/%s /var/www/billing/current/artisan %s\n' "$php" "$worker" | grep -Eq "$worker_pattern"
    done
    if printf '/usr/bin/php8.5 /var/www/other/current/artisan %s\n' "$worker" | grep -Eq "$worker_pattern"; then exit 1; fi
done

printf '%s\n' 'Worker activation checks passed.'
