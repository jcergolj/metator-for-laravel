#!/usr/bin/env bash
set -Eeuo pipefail

: "${METATOR_ACCEPTANCE_HOST:?Set by run-release-gate.sh}"
: "${METATOR_ACCEPTANCE_USER:?Set by run-release-gate.sh}"
: "${METATOR_ACCEPTANCE_IDENTITY:?Set by run-release-gate.sh}"
: "${METATOR_ACCEPTANCE_EVIDENCE_DIR:?Set by run-release-gate.sh}"
: "${GH_TOKEN:?Authenticate gh with repo deploy-key administration access}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOST="$METATOR_ACCEPTANCE_HOST"
USER="$METATOR_ACCEPTANCE_USER"
EVIDENCE_DIR="$METATOR_ACCEPTANCE_EVIDENCE_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/metator-redis-acceptance.XXXXXX")"
APP_REPOSITORY='jcergolj/simpletimer'
APP_BRANCH='master'
PHP_VERSION='8.5'
SSH_OPTIONS=(-i "$METATOR_ACCEPTANCE_IDENTITY" -o BatchMode=yes -o StrictHostKeyChecking=yes)
declare -A DEPLOY_KEY_IDS=()

cleanup() {
    local status=$?
    local site key_id
    for site in "${!DEPLOY_KEY_IDS[@]}"; do
        key_id="${DEPLOY_KEY_IDS[$site]}"
        gh api --silent --method DELETE "repos/${APP_REPOSITORY}/keys/${key_id}" >/dev/null 2>&1 || status=1
    done
    rm -rf "$WORK_DIR"
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$EVIDENCE_DIR"
exec > >(tee -a "$EVIDENCE_DIR/redis-scenario.log") 2>&1

remote() {
    # shellcheck disable=SC2029
    ssh "${SSH_OPTIONS[@]}" "$USER@$HOST" "$1"
}

run_logged() {
    local directory="$1" log_file="$2"
    shift 2
    printf '\n$'
    printf ' %q' "$@"
    printf '\n'
    (cd "$directory" && "$@") 2>&1 | tee -a "$log_file"
}

clone_and_install() {
    local site_id="$1" app_directory log_file
    app_directory="$WORK_DIR/$site_id"
    log_file="$EVIDENCE_DIR/$site_id-setup.log"
    git clone --quiet --depth 1 --branch "$APP_BRANCH" "https://github.com/${APP_REPOSITORY}.git" "$app_directory"
    run_logged "$app_directory" "$log_file" composer install --no-dev --no-interaction --prefer-dist --no-progress
    cp "$app_directory/.env.example" "$app_directory/.env"
    python3 - "$app_directory/composer.json" "$ROOT_DIR" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
package_path = sys.argv[2]
data = json.loads(path.read_text())
data.setdefault("repositories", {})["metator-acceptance"] = {
    "type": "path",
    "url": package_path,
    "options": {
        "symlink": False,
        "versions": {"jcergolj/metator-for-laravel": "dev-master"},
    },
}
path.write_text(json.dumps(data, indent=4) + "\n")
PY
    run_logged "$app_directory" "$log_file" composer require 'jcergolj/metator-for-laravel:dev-master' --update-no-dev --no-install --no-interaction --prefer-dist --no-progress
    run_logged "$app_directory" "$log_file" composer install --no-dev --no-interaction --prefer-dist --no-progress
    run_logged "$app_directory" "$log_file" php artisan key:generate --force --no-interaction
    php "$ROOT_DIR/tests/acceptance/fixtures/generate-redis-site.php" \
        "$app_directory" "$ROOT_DIR" "$site_id" "$HOST" "$USER" | tee -a "$log_file"
}

provision_site() {
    local site_id="$1" app_directory="$2" log_file
    log_file="$EVIDENCE_DIR/$site_id-provision.log"
    local status public_key key_id title
    if (cd "$app_directory" && php artisan metator:provision --config=metator.acceptance.php --no-interaction) >"$log_file" 2>&1; then
        cat "$log_file"
        printf 'Expected first provisioning run to request registration of %s deploy key\n' "$site_id" >&2
        return 1
    else
        status=$?
    fi
    if [[ "$status" != 1 ]] || ! grep -q 'Add the displayed read-only deploy key to GitHub' "$log_file"; then
        cat "$log_file" >&2
        printf 'Unexpected provisioning failure for %s (status %s)\n' "$site_id" "$status" >&2
        return 1
    fi
    cat "$log_file"
    public_key="$(remote "sudo cat /home/deployer/.ssh/git-${site_id}.pub")"
    title="metator-redis-acceptance-${site_id}-$(basename "$EVIDENCE_DIR")"
    key_id="$(gh api "repos/${APP_REPOSITORY}/keys" \
        --method POST \
        --field title="$title" \
        --field key="$public_key" \
        -F read_only=true \
        --jq .id)"
    DEPLOY_KEY_IDS["$site_id"]="$key_id"
    printf 'Registered temporary read-only GitHub deploy key %s for %s\n' "$key_id" "$site_id"
    run_logged "$app_directory" "$log_file" php artisan metator:provision --config=metator.acceptance.php --no-interaction
}

deploy_site() {
    local site_id="$1" app_directory="$2" log_file
    log_file="$EVIDENCE_DIR/$site_id-deploy.log"
    run_logged "$app_directory" "$log_file" vendor/bin/dep deploy production --no-interaction -v
}

get_redis_databases() {
    local site_id="$1"
    remote "sudo awk -F'|' -v site='$site_id' '\$1 == site { print \$2, \$3 }' /var/lib/metator/redis-allocations.tsv"
}

get_worker_pid() {
    local site_id="$1" status
    status="$(remote "sudo supervisorctl status ${site_id}-worker:${site_id}-worker")"
    [[ "$status" == *'RUNNING'* ]] || { printf 'Worker is not running: %s\n' "$status" >&2; return 1; }
    [[ "$status" =~ pid[[:space:]]+([0-9]+) ]] || { printf 'Worker PID missing from status: %s\n' "$status" >&2; return 1; }
    printf '%s\n' "${BASH_REMATCH[1]}"
}

wait_for_https() {
    local site_id="$1" domain="${1}.${HOST}.sslip.io" status=''
    for _ in {1..90}; do
        status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' "https://${domain}/" 2>/dev/null || true)"
        [[ "$status" == 200 ]] && return 0
        sleep 5
    done
    printf 'HTTPS check failed for %s: last status %s\n' "$domain" "$status" >&2
    return 1
}

clone_and_install redis-one
site_one="$WORK_DIR/redis-one"
clone_and_install redis-two
site_two="$WORK_DIR/redis-two"
printf '\n== Shared server preparation ==\n'
run_logged "$site_one" "$EVIDENCE_DIR/server-preparation.log" \
    php artisan metator:prepare-server --config=metator.acceptance.php

printf '\n== Provision sites and deploy separately ==\n'
provision_site redis-one "$site_one"
deploy_site redis-one "$site_one"
provision_site redis-two "$site_two"
deploy_site redis-two "$site_two"

wait_for_https redis-one
wait_for_https redis-two
scp "$ROOT_DIR/tests/acceptance/fixtures/redis-cache-probe.php" \
    "$USER@$HOST:/tmp/metator-redis-cache-probe.php"

read -r one_cache one_runtime < <(get_redis_databases redis-one)
read -r two_cache two_runtime < <(get_redis_databases redis-two)
[[ "$one_cache" =~ ^[0-9]+$ && "$one_runtime" =~ ^[0-9]+$ ]]
[[ "$two_cache" =~ ^[0-9]+$ && "$two_runtime" =~ ^[0-9]+$ ]]
[[ "$one_cache" != "$one_runtime" && "$two_cache" != "$two_runtime" ]]
[[ "$one_cache" != "$two_cache" && "$one_cache" != "$two_runtime" && "$one_runtime" != "$two_cache" && "$one_runtime" != "$two_runtime" ]]

printf '\n== Seed cache and runtime state ==\n'
remote "cd /var/www/redis-one/current && sudo -u www-data /usr/bin/php${PHP_VERSION} /tmp/metator-redis-cache-probe.php put metator-acceptance-cache redis-one-cache"
remote "cd /var/www/redis-two/current && sudo -u www-data /usr/bin/php${PHP_VERSION} /tmp/metator-redis-cache-probe.php put metator-acceptance-cache redis-two-cache"
one_queue_size="$(remote 'cd /var/www/redis-one/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php queue-put ignored')"
two_queue_size="$(remote 'cd /var/www/redis-two/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php queue-put ignored')"
[[ "$one_queue_size" == 1 && "$two_queue_size" == 1 ]]
one_session_id="$(remote 'cd /var/www/redis-one/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php session-put metator-acceptance-session redis-one-session')"
two_session_id="$(remote 'cd /var/www/redis-two/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php session-put metator-acceptance-session redis-two-session')"
for pair in "redis-one:$one_runtime" "redis-two:$two_runtime"; do
    site_id="${pair%%:*}"
    runtime_db="${pair#*:}"
    remote "sudo redis-cli -n ${runtime_db} SET metator-acceptance:${site_id}:horizon preserved-${site_id}-horizon >/dev/null"
done

printf '\n== Clear one site cache and verify isolation ==\n'
remote 'cd /var/www/redis-one/current && sudo -u www-data /usr/bin/php8.5 artisan cache:clear'
one_cache_value="$(remote 'cd /var/www/redis-one/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php has metator-acceptance-cache')"
two_cache_value="$(remote 'cd /var/www/redis-two/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php get metator-acceptance-cache')"
[[ "$one_cache_value" == missing ]]
[[ "$two_cache_value" == redis-two-cache ]]
[[ "$(remote 'cd /var/www/redis-one/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php queue-size ignored')" == "$one_queue_size" ]]
[[ "$(remote 'cd /var/www/redis-two/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php queue-size ignored')" == "$two_queue_size" ]]
[[ "$(remote "cd /var/www/redis-one/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php session-get metator-acceptance-session ${one_session_id}")" == redis-one-session ]]
[[ "$(remote "cd /var/www/redis-two/current && sudo -u www-data /usr/bin/php8.5 /tmp/metator-redis-cache-probe.php session-get metator-acceptance-session ${two_session_id}")" == redis-two-session ]]
for pair in "redis-one:$one_runtime" "redis-two:$two_runtime"; do
    site_id="${pair%%:*}"
    runtime_db="${pair#*:}"
    value="$(remote "sudo redis-cli -n ${runtime_db} GET metator-acceptance:${site_id}:horizon")"
    [[ "$value" == "preserved-${site_id}-horizon" ]]
done

printf '\n== Restart one site worker and verify the other is untouched ==\n'
one_worker_before="$(get_worker_pid redis-one)"
two_worker_before="$(get_worker_pid redis-two)"
deploy_site redis-one "$site_one"
one_worker_after="$(get_worker_pid redis-one)"
two_worker_after="$(get_worker_pid redis-two)"
[[ "$one_worker_after" != "$one_worker_before" ]]
[[ "$two_worker_after" == "$two_worker_before" ]]

{
    printf 'target_ubuntu=%s\n' "$METATOR_ACCEPTANCE_UBUNTU_RELEASE"
    printf 'target_host=%s\n' "$HOST"
    printf 'php=%s\n' "$(remote '/usr/bin/php8.5 -r "echo PHP_VERSION;"')"
    printf 'redis=%s\n' "$(remote 'redis-server --version')"
    printf 'application_repository=%s\n' "$APP_REPOSITORY"
    printf 'application_branch=%s\n' "$APP_BRANCH"
    printf 'application_revision=%s\n' "$(git -C "$site_one" rev-parse HEAD)"
    printf 'metator_revision=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD)"
    printf 'site_redis_one_cache_db=%s\nsite_redis_one_runtime_db=%s\n' "$one_cache" "$one_runtime"
    printf 'site_redis_two_cache_db=%s\nsite_redis_two_runtime_db=%s\n' "$two_cache" "$two_runtime"
    printf 'redis_one_cache_after_clear=%s\nredis_two_cache_after_clear=%s\n' "$one_cache_value" "$two_cache_value"
    printf 'redis_one_queue_size_after_clear=%s\nredis_two_queue_size_after_clear=%s\n' "$one_queue_size" "$two_queue_size"
    printf 'redis_one_session_after_clear=preserved\nredis_two_session_after_clear=preserved\n'
    printf 'redis_one_worker_pid_before=%s\nredis_one_worker_pid_after=%s\n' "$one_worker_before" "$one_worker_after"
    printf 'redis_two_worker_pid_before=%s\nredis_two_worker_pid_after=%s\n' "$two_worker_before" "$two_worker_after"
    printf 'result=passed\n'
} > "$EVIDENCE_DIR/redis-isolation.txt"

printf '\nRedis site-isolation acceptance passed; evidence: %s/redis-isolation.txt\n' "$EVIDENCE_DIR"
