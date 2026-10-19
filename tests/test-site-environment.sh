#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/04-shared-env.sh"

# Exercise real environment writes without requiring privileged file ownership.
sudo() {
    if [[ "$1" == install ]]; then
        shift
        local arguments=()
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                -o|-g) shift 2 ;;
                *) arguments+=("$1"); shift ;;
            esac
        done
        command install "${arguments[@]}"
        return
    fi
    "$@"
}

SITE_ID=sqlite-site
APP_NAME="$SITE_ID"
APP_FOLDER="$TEST_DIR/$SITE_ID"
DOMAIN=sqlite.example.test
DATABASE_DRIVER=sqlite
ENV_SEED_FILE="$TEST_DIR/local.env"
cat > "$ENV_SEED_FILE" <<'ENV'
APP_ENV=local
APP_DEBUG=true
APP_KEY=local-key
APP_URL=http://localhost
DB_CONNECTION=mysql
DB_DATABASE=local
DB_USERNAME=root
DB_PASSWORD=local-password
CACHE_STORE=database
SESSION_DRIVER=database
SESSION_DOMAIN=localhost
SESSION_COOKIE=shared_local_session
SESSION_SECURE_COOKIE=false
QUEUE_CONNECTION=redis
DB_QUEUE_CONNECTION=local-database
LOG_LEVEL=debug
MAIL_HOST=custom-mail.example.test
FILESYSTEM_DISK=s3
CUSTOM_SECRET=keep-me
ENV

step_shared_env
environment="$APP_FOLDER/shared/.env"
for assignment in \
    'DB_CONNECTION="sqlite"' \
    "DB_DATABASE=\"$APP_FOLDER/shared/database/database.sqlite\"" \
    'DB_USERNAME=""' 'DB_PASSWORD=""' \
    'CACHE_STORE="file"' 'SESSION_DRIVER="file"' \
    'SESSION_DOMAIN=""' 'SESSION_COOKIE="metator_sqlite-site_session"' \
    'SESSION_SECURE_COOKIE="true"' 'QUEUE_CONNECTION="sync"' \
    'LOG_LEVEL="info"' 'MAIL_HOST=custom-mail.example.test' \
    'FILESYSTEM_DISK=s3' 'CUSTOM_SECRET=keep-me'; do
    grep -Fxq "$assignment" "$environment"
done

# Operator changes and generated credentials survive ordinary reruns.
sed -i 's/^LOG_LEVEL=.*/LOG_LEVEL=warning/' "$environment"
printf '\nOPERATOR_VALUE=production-only\n' >> "$environment"
cp "$environment" "$TEST_DIR/before"
step_shared_env
cmp "$TEST_DIR/before" "$environment"

# MariaDB receives site-owned credentials, and standard workers use its queue.
SITE_ID=mysql-site
APP_NAME="$SITE_ID"
APP_FOLDER="$TEST_DIR/$SITE_ID"
DOMAIN=mysql.example.test
DATABASE_DRIVER=mysql
DATABASE_CONFIG_READY=false
USE_QUEUE=true
step_shared_env
environment="$APP_FOLDER/shared/.env"
for assignment in \
    'DB_CONNECTION="mysql"' 'DB_HOST="127.0.0.1"' 'DB_PORT="3306"' \
    'DB_DATABASE="metator_mysql_site"' 'DB_USERNAME="metator_mysql_site"' \
    'QUEUE_CONNECTION="database"' 'DB_QUEUE_CONNECTION="mysql"' \
    'CACHE_STORE="file"' 'SESSION_DRIVER="file"'; do
    grep -Fxq "$assignment" "$environment"
done
grep -Eq '^DB_PASSWORD="[A-Za-z0-9+/=]{48}"$' "$environment"
cp "$environment" "$TEST_DIR/before"
DATABASE_CONFIG_READY=false
step_shared_env
cmp "$TEST_DIR/before" "$environment"

# Redis cache and runtime connections must not inherit local connection routing.
cat >> "$ENV_SEED_FILE" <<'ENV'
SESSION_CONNECTION=cache
SESSION_STORE=file
REDIS_CACHE_CONNECTION=default
REDIS_CACHE_LOCK_CONNECTION=cache
REDIS_QUEUE_CONNECTION=cache
ENV
for capability in cache queue; do
    USE_QUEUE=true
    USE_HORIZON=false
    if [[ "$capability" == queue ]]; then
        USE_HORIZON=true
    fi
    SITE_ID="redis-$capability"
    APP_NAME="$SITE_ID"
    APP_FOLDER="$TEST_DIR/$SITE_ID"
    DOMAIN="$SITE_ID.example.test"
    DATABASE_DRIVER=sqlite
    DATABASE_CONFIG_READY=false
    USE_REDIS=true
    REDIS_CAPABILITY="$capability"
    # Allocation itself is covered by test-redis.sh; provide its known result.
    REDIS_CONFIG_READY=true
    REDIS_CACHE_DB=3
    REDIS_RUNTIME_DB=4
    step_shared_env
    environment="$APP_FOLDER/shared/.env"
    for assignment in \
        'CACHE_STORE="redis"' 'SESSION_DRIVER="redis"' \
        'SESSION_CONNECTION="default"' 'SESSION_STORE="redis"' 'REDIS_CACHE_CONNECTION="cache"' \
        'REDIS_CACHE_LOCK_CONNECTION="default"' 'REDIS_QUEUE_CONNECTION="default"' \
        'REDIS_CACHE_DB="3"' 'REDIS_DB="4"'; do
        grep -Fxq "$assignment" "$environment"
    done
    if [[ "$capability" == queue ]]; then
        grep -Fxq 'QUEUE_CONNECTION="redis"' "$environment"
    else
        grep -Fxq 'QUEUE_CONNECTION="database"' "$environment"
    fi
    cp "$environment" "$TEST_DIR/before"
    step_shared_env
    cmp "$TEST_DIR/before" "$environment"
done

# A failed Redis allocation must not leave local routing or database credentials
# behind when provisioning resumes against the already-created environment.
SITE_ID=redis-retry
APP_NAME="$SITE_ID"
APP_FOLDER="$TEST_DIR/$SITE_ID"
DOMAIN=retry.example.test
DATABASE_DRIVER=mysql
DATABASE_CONFIG_READY=false
USE_QUEUE=false
USE_HORIZON=false
USE_REDIS=true
REDIS_CAPABILITY=cache
REDIS_CONFIG_READY=false
mkdir -p "$APP_FOLDER"
touch "$APP_FOLDER/.metator-site"
printf 'REDIS_URL=redis://localhost:6380/0\nREDIS_PASSWORD=local-password\n' >> "$ENV_SEED_FILE"
# The sudo test shim invokes shell functions in the current process.
# shellcheck disable=SC2032
redis-cli() { return 1; }
if step_shared_env; then
    printf 'Expected allocation failure\n' >&2
    exit 1
fi
environment="$APP_FOLDER/shared/.env"
production_key="$(grep '^APP_KEY=' "$environment")"
DATABASE_CONFIG_READY=false
REDIS_CONFIG_READY=true
REDIS_CACHE_DB=5
REDIS_RUNTIME_DB=6
step_shared_env
for assignment in \
    'DB_DATABASE="metator_redis_retry"' 'DB_USERNAME="metator_redis_retry"' \
    'REDIS_URL=""' 'REDIS_PASSWORD=""' 'SESSION_CONNECTION="default"' \
    'SESSION_STORE="redis"' 'REDIS_CACHE_CONNECTION="cache"' \
    'QUEUE_CONNECTION="sync"' "$production_key"; do
    grep -Fxq "$assignment" "$environment"
done

# Valid dotenv whitespace/export syntax and duplicate keys cannot retain local
# connection overrides. Matching reruns must still leave the environment alone.
SITE_ID=connection-overrides
APP_NAME="$SITE_ID"
APP_FOLDER="$TEST_DIR/$SITE_ID"
DOMAIN=overrides.example.test
DATABASE_DRIVER=mysql
DATABASE_CONFIG_READY=false
USE_REDIS=true
REDIS_CONFIG_READY=true
cat > "$ENV_SEED_FILE" <<'ENV'
DB_URL=mysql://first-local/database
export DB_URL = mysql://last-local/database
export DB_SOCKET = /local-only/mysql.sock
  REDIS_URL = redis://local-only.example:6380/0
export REDIS_USERNAME=local-user
REDIS_PASSWORD = local-password
CUSTOM_SECRET=keep-me
CUSTOM_TEMPLATE="prefix
DB_URL=mysql://embedded-custom/database
REDIS_PASSWORD=embedded-custom-password
APP_ENV=custom-template
suffix"
ENV
step_shared_env
environment="$APP_FOLDER/shared/.env"
for key in DB_URL DB_SOCKET REDIS_URL REDIS_USERNAME REDIS_PASSWORD; do
    grep -Fxq "${key}=\"\"" "$environment"
done
if grep -qE 'first-local|last-local|local-only|local-user|local-password' "$environment"; then
    printf 'Local connection settings survived production initialization\n' >&2
    exit 1
fi
grep -Fxq 'CUSTOM_SECRET=keep-me' "$environment"
grep -Fxq 'DB_URL=mysql://embedded-custom/database' "$environment"
grep -Fxq 'REDIS_PASSWORD=embedded-custom-password' "$environment"
grep -Fxq 'APP_ENV=custom-template' "$environment"
cp "$environment" "$TEST_DIR/before"
DATABASE_CONFIG_READY=false
step_shared_env
cmp "$TEST_DIR/before" "$environment"

printf 'Site environment defaults checks passed.\n'
