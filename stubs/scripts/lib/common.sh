#!/usr/bin/env bash
# shellcheck disable=SC2034

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DEPLOY_USER="deployer"
GITHUB_KEY=''
GITHUB_ALIAS='__GIT_DEPLOYER_NAME__'
GITHUB_URL=''
GITHUB_CONFIG_MARKER=''

step_number=0
STEP_SUCCESSFUL=()
STEP_FAILED=()
STEP_SKIPPED=()

die() { echo -e "${RED}[ERROR]${NC} $*" >&2; return 1; }
step() { echo -e "${GREEN}[STEP]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

USE_CLOUDFLARE=false
CLOUDFLARE_CONFIG_READY=false
DATABASE_DRIVER=''
DATABASE_CONFIG_READY=false
USE_SCHEDULER=false
USE_QUEUE=false
USE_HORIZON=false
USE_REDIS=false
REDIS_CAPABILITY=none
CONFIGURE_DEPLOY_USER_LOGIN=false
CLIENT_PUBLIC_KEY="${CLIENT_PUBLIC_KEY:-}"
ENV_FILE_CREATED=false
ENV_UPDATED=false
REDIS_CONFIG_READY=false
REDIS_CACHE_DB=''
REDIS_RUNTIME_DB=''
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

configure_github_identity() {
    GITHUB_KEY="/home/${DEPLOY_USER}/.ssh/${GITHUB_ALIAS}"
    GITHUB_URL="git@${GITHUB_ALIAS}:${GITHUB_REPOSITORY}.git"
    GITHUB_CONFIG_MARKER="LARAVEL DEPLOYER GITHUB ${APP_NAME}"
}

ensure_deploy_user_exists() {
    if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
        sudo useradd --create-home --shell /bin/bash "$DEPLOY_USER"
        ok "Created deployment user: $DEPLOY_USER"
    fi
}

prepare_deploy_user() {
    ensure_deploy_user_exists || return 1
    if ! getent group www-data >/dev/null 2>&1; then
        sudo groupadd --system www-data || return 1
    fi
    if ! id -nG "$DEPLOY_USER" | tr ' ' '\n' | grep -qx www-data; then
        sudo usermod -aG www-data "$DEPLOY_USER" || return 1
    fi
}

require_commands() {
    local command
    for command in "$@"; do
        command -v "$command" >/dev/null 2>&1 || {
            die "$command must already be installed before bootstrap starts"
            return 1
        }
    done
}

claim_application_folder() {
    local identity_file="$APP_FOLDER/.metator-site"
    if sudo test -L "$APP_FOLDER"; then
        die "Application folder must not be a symlink: $APP_FOLDER"
        return 1
    fi
    if sudo test -e "$APP_FOLDER" && ! sudo test -f "$identity_file"; then
        die "Application folder is unmarked and cannot be adopted: $APP_FOLDER"
        return 1
    fi
    if sudo test -e "$identity_file"; then
        if ! sudo grep -qxF "site_id=$SITE_ID" "$identity_file" ||
            ! sudo grep -qxF "repository=$GITHUB_REPOSITORY" "$identity_file" ||
            ! sudo grep -qxF "php_version=$PHP_VERSION" "$identity_file" ||
            ! sudo grep -qxF "database=$DATABASE_DRIVER" "$identity_file"; then
            die "Application folder belongs to another site or runtime: $APP_FOLDER"
            return 1
        fi

        return
    fi
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER" || return 1
    printf '%s\n' \
        "site_id=$SITE_ID" \
        "repository=$GITHUB_REPOSITORY" \
        "php_version=$PHP_VERSION" \
        "database=$DATABASE_DRIVER" |
        sudo install -m 640 -o "$DEPLOY_USER" -g www-data /dev/stdin "$identity_file" || return 1
}

prompt_value() {
    local prompt="$1" variable="$2" default="${3:-}" value
    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " value
        value="${value:-$default}"
    else
        read -r -p "$prompt: " value
    fi
    if [[ -z "$value" ]]; then
        die "$prompt is required"
        return 1
    fi
    printf -v "$variable" '%s' "$value"
}

prompt_secret() {
    local prompt="$1" variable="$2" value
    read -r -s -p "$prompt: " value
    echo
    if [[ -z "$value" ]]; then
        die "$prompt is required"
        return 1
    fi
    printf -v "$variable" '%s' "$value"
}

skip_step() {
    local title="$1"
    step_number=$((step_number + 1))
    STEP_SKIPPED+=("STEP ${step_number} - ${title}")
    warn "Skipped: $title"
}

run_step() {
    local title="$1" description="$2" function_name="$3" status
    step_number=$((step_number + 1))
    echo
    echo -e "${GREEN}STEP ${step_number} — ${title}${NC}"
    echo "$description"
    echo
    set +e
    "$function_name"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        STEP_SUCCESSFUL+=("STEP ${step_number} - ${title}")
        return
    fi
    if [[ "$status" -eq 75 ]]; then
        warn "Waiting for local confirmation: $title"
        return "$status"
    fi
    STEP_FAILED+=("STEP ${step_number} - ${title} (exit status ${status})")
    warn "Step failed: $title"
    return "$status"
}

print_step_group() {
    local heading="$1"
    shift

    echo "$heading"
    if [[ "$#" -eq 0 ]]; then
        echo '  none'
        return
    fi

    local item
    for item in "$@"; do
        echo "  - $item"
    done
}

print_step_summary() {
    echo
    echo 'Step summary'
    print_step_group 'Performed successfully:' "${STEP_SUCCESSFUL[@]}"
    print_step_group 'Failed:' "${STEP_FAILED[@]}"
    if [[ "${#STEP_FAILED[@]}" -gt 0 ]]; then
        print_step_group 'Skipped:' "${STEP_SKIPPED[@]}"
        warn 'Selected steps failed. Correct the failures and rerun the bootstrap.'
    fi
}

step_metadata() {
    local file="$1" key="$2"
    sed -nE "s/^# @${key}:[[:space:]]*(.*)$/\1/p" "$file" | sed -n '1p'
}

validate_step_metadata() {
    local step_file id title group required default order normalized
    local -A seen=()
    for step_file in "$SCRIPT_DIR"/steps/*.sh; do
        [[ -f "$step_file" ]] || continue
        id="$(step_metadata "$step_file" id)"
        title="$(step_metadata "$step_file" title)"
        group="$(step_metadata "$step_file" group)"
        required="$(step_metadata "$step_file" required)"
        default="$(step_metadata "$step_file" default)"
        order="$(step_metadata "$step_file" order)"
        [[ "$id" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || { die "Invalid @id in $step_file: $id"; return 1; }
        [[ -n "$title" ]] || { die "Empty @title in $step_file"; return 1; }
        [[ -n "$group" ]] || { die "Empty @group in $step_file"; return 1; }
        [[ "$required" == true || "$required" == false ]] || { die "Invalid @required in $step_file: $required"; return 1; }
        [[ "$default" == true || "$default" == false ]] || { die "Invalid @default in $step_file: $default"; return 1; }
        [[ "$order" =~ ^(0|[1-9][0-9]*)$ ]] || { die "Invalid @order in $step_file: $order"; return 1; }
        normalized="${id//-/_}"
        [[ -z "${seen[$normalized]+x}" ]] || { die "Duplicate normalized step ID $normalized in $step_file"; return 1; }
        seen[$normalized]="$step_file"
    done
}

validate_step_functions() {
    local step_file id function_name
    for step_file in "$SCRIPT_DIR"/steps/*.sh; do
        [[ -f "$step_file" ]] || continue
        id="$(step_metadata "$step_file" id)"
        function_name="step_${id//-/_}"
        declare -F "$function_name" >/dev/null || { die "Step function is missing: $function_name ($step_file)"; return 1; }
    done
}

run_selected_steps() {
    local step_file id title required order function_name status
    local -a discovered=()

    for step_file in "$SCRIPT_DIR"/steps/*.sh; do
        [[ -f "$step_file" ]] || continue
        id="$(step_metadata "$step_file" id)"
        title="$(step_metadata "$step_file" title)"
        required="$(step_metadata "$step_file" required)"
        order="$(step_metadata "$step_file" order)"
        function_name="step_${id//-/_}"
        discovered+=("${order}|${step_file}|${title}|${required}|${function_name}")
    done

    while IFS='|' read -r order step_file title required function_name; do
        if [[ "$METATOR_OPERATION" == prepare-server ]]; then
            case "$(step_metadata "$step_file" id)" in
                prerequisites|node) ;;
                *) continue ;;
            esac
        fi
        if run_step "$title" "Runs ${title}." "$function_name"; then
            status=0
        else
            status=$?
        fi
        if [[ "$status" -ne 0 ]]; then
            return "$status"
        fi
    done < <(printf '%s\n' "${discovered[@]}" | sort -t '|' -k1,1n -k2,2)
    return 0
}

require_safe_inputs() {
    [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
        { die 'GitHub repository must look like owner/repository'; return 1; }
    [[ "${#SITE_ID}" -le 32 && "$SITE_ID" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] ||
        { die 'Site ID must be 1-32 lowercase letters or digits with single hyphens'; return 1; }
    [[ "$APP_FOLDER" =~ ^/var/www/[A-Za-z0-9_.-]+$ && "$APP_FOLDER" != /var/www/. && "$APP_FOLDER" != /var/www/.. ]] ||
        { die 'Application folder must be a simple path under /var/www'; return 1; }
    [[ "$APP_FOLDER" == "/var/www/${SITE_ID}" ]] ||
        { die 'Application folder must be derived from the site ID'; return 1; }
    [[ "$GITHUB_ALIAS" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
        { die 'Invalid Git SSH deployer name'; return 1; }
    case "${GITHUB_ALIAS,,}" in
        config|authorized_keys*|known_hosts*|environment|rc|*.pub)
            die 'Git SSH deployer name collides with a reserved SSH filename'
            return 1 ;;
    esac
    [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] ||
        { die 'Invalid domain'; return 1; }
    [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        die 'Invalid server IPv4 address'
}

ensure_cloudflare_config() {
    if [[ "$CLOUDFLARE_CONFIG_READY" == true ]]; then
        return
    fi

    if [[ "$USE_CLOUDFLARE" != true ]]; then
        CLOUDFLARE_CONFIG_READY=true

        return
    fi

    [[ -n "${CF_TOKEN:-}" ]] || prompt_secret 'Cloudflare API token' CF_TOKEN || return 1
    [[ -n "${CF_ZONE_ID:-}" ]] || prompt_value 'Cloudflare zone ID' CF_ZONE_ID || return 1
    if [[ ! "$CF_ZONE_ID" =~ ^[A-Za-z0-9]+$ ]]; then
        die 'Invalid Cloudflare zone ID'
        return 1
    fi

    CLOUDFLARE_CONFIG_READY=true
}

set_env_value() {
    local key="$1" value="$2" escaped temporary source_file line
    escaped="${value//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//\$/\\\$}"
    local desired="${key}=\"${escaped}\""
    local env_file="${ENV_FILE:-$APP_FOLDER/shared/.env}"
    if sudo grep -Fxq "$desired" "$env_file"; then
        return
    fi
    if sudo grep -qE "^${key}=" "$env_file"; then
        temporary="$(mktemp)"
        source_file="$(mktemp)"
        sudo sed -n '1,$p' "$env_file" | tee "$source_file" >/dev/null
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "$key="* ]]; then
                printf '%s\n' "${key}=\"${escaped}\""
            else
                printf '%s\n' "$line"
            fi
        done < "$source_file" > "$temporary"
        sudo cp "$temporary" "$env_file"
        rm -f "$temporary" "$source_file"
    else
        printf '%s\n' "${key}=\"${escaped}\"" |
            sudo tee -a "$env_file" >/dev/null
    fi
    ENV_UPDATED=true
}

merge_env_example() {
    local example_file="$1" env_file="$2" line key
    ENV_UPDATED=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
        key="${BASH_REMATCH[1]}"
        if ! sudo grep -qE "^${key}=" "$env_file"; then
            printf '%s\n' "$line" | sudo tee -a "$env_file" >/dev/null
            ENV_UPDATED=true
        fi
    done < "$example_file"
}

ensure_production_env() {
    local env_file="$1" app_key=''
    if [[ "$ENV_FILE_CREATED" == true ]] || ! env_key_exists APP_ENV "$env_file"; then
        set_env_value APP_ENV production
    fi
    if [[ "$ENV_FILE_CREATED" == true ]] || ! env_key_exists APP_DEBUG "$env_file"; then
        set_env_value APP_DEBUG false
    fi
    if env_key_exists APP_KEY "$env_file"; then
        read_env_value APP_KEY "$env_file" app_key
    fi
    if [[ -z "$app_key" || "$app_key" == __* ]]; then
        set_env_value APP_KEY "base64:$(openssl rand -base64 32 | tr -d '\n')"
    fi
    if sudo grep -qE '__[A-Z0-9_]+__' "$env_file"; then
        die "Unresolved placeholder remains in $env_file"
        return 1
    fi
}

env_key_exists() {
    local key="$1" env_file="$2"
    sudo grep -qE "^${key}=" "$env_file"
}

read_env_value() {
    local key="$1" env_file="$2" variable="$3" value
    value="$(sudo sed -nE "s/^${key}=(.*)$/\1/p" "$env_file" | sed -n '1p')"
    value="${value#\"}"
    value="${value%\"}"
    printf -v "$variable" '%s' "$value"
}

configure_database_env() {
    if [[ "$DATABASE_DRIVER" == sqlite ]]; then
        set_env_value DB_CONNECTION sqlite
        set_env_value DB_DATABASE "$APP_FOLDER/shared/database/database.sqlite"
        set_env_value DB_HOST ''
        set_env_value DB_PORT ''
        set_env_value DB_USERNAME ''
        set_env_value DB_PASSWORD ''
        return
    fi

    set_env_value DB_CONNECTION mysql
    set_env_value DB_HOST "$MYSQL_HOST"
    set_env_value DB_PORT "$MYSQL_PORT"
    set_env_value DB_DATABASE "$MYSQL_DATABASE"
    set_env_value DB_USERNAME "$MYSQL_USERNAME"
    set_env_value DB_PASSWORD "$MYSQL_PASSWORD"
}

site_database_name() {
    printf 'metator_%s\n' "${SITE_ID//-/_}"
}

site_database_user() {
    printf 'metator_%s\n' "${SITE_ID//-/_}"
}

site_metadata_value() {
    local key="$1" metadata_file="$APP_FOLDER/.metator-site"
    sudo sed -nE "s/^${key}=(.*)$/\1/p" "$metadata_file" | sed -n '1p'
}

record_site_database() {
    local metadata_file="$APP_FOLDER/.metator-site"
    if ! sudo grep -q '^database_name=' "$metadata_file"; then
        printf '%s\n' \
            "database_name=$MYSQL_DATABASE" \
            "database_user=$MYSQL_USERNAME" \
            "database_host=$MYSQL_HOST" |
            sudo tee -a "$metadata_file" >/dev/null || return 1
    fi
}

record_redis_allocation() {
    local metadata_file="$APP_FOLDER/.metator-site"
    if ! sudo grep -q '^redis_cache_db=' "$metadata_file"; then
        printf '%s\n' "redis_cache_db=$REDIS_CACHE_DB" "redis_runtime_db=$REDIS_RUNTIME_DB" |
            sudo tee -a "$metadata_file" >/dev/null || return 1
    fi
}

record_site_scheduler() {
    local metadata_file="$APP_FOLDER/.metator-site"
    local scheduler_file="${SCHEDULER_FILE:-/etc/cron.d/metator-${SITE_ID}}"
    if ! sudo grep -q '^scheduler_file=' "$metadata_file"; then
        printf '%s\n' "scheduler_file=$scheduler_file" |
            sudo tee -a "$metadata_file" >/dev/null || return 1
    fi
}

record_site_domain() {
    local metadata_file="$APP_FOLDER/.metator-site"
    if ! sudo grep -q '^domain=' "$metadata_file"; then
        printf '%s\n' "domain=$DOMAIN" | sudo tee -a "$metadata_file" >/dev/null || return 1
    fi
}

ensure_redis_config() {
    if [[ "$REDIS_CONFIG_READY" == true ]]; then
        return
    fi
    [[ "$USE_REDIS" == true ]] || { REDIS_CONFIG_READY=true; return; }

    local metadata_cache metadata_runtime reservation allocated cache_db runtime_db databases dbsize
    metadata_cache="$(site_metadata_value redis_cache_db)"
    metadata_runtime="$(site_metadata_value redis_runtime_db)"
    if [[ -n "$metadata_cache" || -n "$metadata_runtime" ]]; then
        [[ "$metadata_cache" =~ ^[0-9]+$ && "$metadata_runtime" =~ ^[0-9]+$ &&
            "$metadata_cache" != "$metadata_runtime" ]] || {
            die 'Redis allocation metadata is invalid'
            return 1
        }
        REDIS_CACHE_DB="$metadata_cache"
        REDIS_RUNTIME_DB="$metadata_runtime"
    else
        databases="$(sudo redis-cli --raw CONFIG GET databases | sed -n '2p')" || return 1
        [[ "$databases" =~ ^[1-9][0-9]*$ ]] || { die 'Redis returned an invalid database capacity'; return 1; }
        sudo install -d -m 2775 -o root -g www-data "$(dirname "$REDIS_ALLOCATION_FILE")" || return 1
        sudo touch "$REDIS_ALLOCATION_FILE" || return 1
        reservation="$(sudo sed -nE "s/^${SITE_ID}\|([0-9]+)\|([0-9]+)$/\1 \2/p" "$REDIS_ALLOCATION_FILE" | sed -n '1p')"
        if [[ "$reservation" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ && "${BASH_REMATCH[1]}" != "${BASH_REMATCH[2]}" ]]; then
            REDIS_CACHE_DB="${BASH_REMATCH[1]}"
            REDIS_RUNTIME_DB="${BASH_REMATCH[2]}"
            record_redis_allocation || return 1
            REDIS_CONFIG_READY=true
            return
        fi
        allocated="$(sudo sed -nE 's/^[^|]+\|([0-9]+)\|([0-9]+)$/\1 \2/p' "$REDIS_ALLOCATION_FILE")"
        for ((cache_db=1; cache_db<databases; cache_db++)); do
            [[ " $allocated " != *" $cache_db "* ]] || continue
            dbsize="$(sudo redis-cli -n "$cache_db" DBSIZE)" || return 1
            [[ "$dbsize" == 0 ]] || continue
            for ((runtime_db=cache_db+1; runtime_db<databases; runtime_db++)); do
                [[ " $allocated " != *" $runtime_db "* ]] || continue
                dbsize="$(sudo redis-cli -n "$runtime_db" DBSIZE)" || return 1
                [[ "$dbsize" == 0 ]] || continue
                REDIS_CACHE_DB="$cache_db"
                REDIS_RUNTIME_DB="$runtime_db"
                printf '%s|%s|%s\n' "$SITE_ID" "$cache_db" "$runtime_db" |
                    sudo tee -a "$REDIS_ALLOCATION_FILE" >/dev/null || return 1
                break 2
            done
        done
        if [[ -z "$REDIS_CACHE_DB" ]]; then
            die 'Redis has no two unreserved empty logical databases; run explicit server preparation'
            return 1
        fi
    fi
    record_redis_allocation || return 1
    REDIS_CONFIG_READY=true
}

configure_redis_env() {
    set_env_value REDIS_HOST "$REDIS_HOST"
    set_env_value REDIS_PORT "$REDIS_PORT"
    set_env_value REDIS_DB "$REDIS_RUNTIME_DB"
    set_env_value REDIS_CACHE_DB "$REDIS_CACHE_DB"
    set_env_value CACHE_STORE redis
    set_env_value SESSION_DRIVER redis
    if [[ "$REDIS_CAPABILITY" == queue ]]; then
        set_env_value QUEUE_CONNECTION redis
    fi
}

ensure_database_config() {
    if [[ "$DATABASE_CONFIG_READY" == true ]]; then
        return
    fi

    if [[ "$DATABASE_DRIVER" == sqlite ]]; then
        DATABASE_CONFIG_READY=true

        return
    fi
    if [[ "$DATABASE_DRIVER" != mysql ]]; then
        die 'Invalid database selection'

        return 1
    fi

    local env_file="$APP_FOLDER/shared/.env"
    local expected_database expected_user
    expected_database="$(site_database_name)"
    expected_user="$(site_database_user)"
    if [[ "$ENV_FILE_CREATED" != true ]] && env_key_exists DB_HOST "$env_file" &&
        env_key_exists DB_PORT "$env_file" && env_key_exists DB_DATABASE "$env_file" &&
        env_key_exists DB_USERNAME "$env_file" && env_key_exists DB_PASSWORD "$env_file"; then
        read_env_value DB_HOST "$env_file" MYSQL_HOST
        read_env_value DB_PORT "$env_file" MYSQL_PORT
        read_env_value DB_DATABASE "$env_file" MYSQL_DATABASE
        read_env_value DB_USERNAME "$env_file" MYSQL_USERNAME
        read_env_value DB_PASSWORD "$env_file" MYSQL_PASSWORD
        if [[ "$MYSQL_DATABASE" != "$expected_database" || "$MYSQL_USERNAME" != "$expected_user" ||
            "$MYSQL_HOST" != 127.0.0.1 || "$MYSQL_PORT" != 3306 ]]; then
            die 'Existing MySQL settings are not owned by this site'
            return 1
        fi
    else
        MYSQL_HOST=127.0.0.1
        MYSQL_PORT=3306
        MYSQL_DATABASE="$expected_database"
        MYSQL_USERNAME="$expected_user"
        MYSQL_PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"
    fi

    DATABASE_CONFIG_READY=true
}
