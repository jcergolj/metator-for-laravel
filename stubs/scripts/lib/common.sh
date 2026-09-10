#!/usr/bin/env bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DEPLOY_USER="deployer"
GITHUB_KEY=''
GITHUB_ALIAS='__GIT_DEPLOYER_NAME__'
GITHUB_URL=''
GITHUB_CONFIG_MARKER=''
CADDY_CERT="/etc/caddy/certs/cloudflare-wildcard.crt"
CADDY_KEY="/etc/caddy/certs/cloudflare-wildcard.key"

step_number=0
STEP_SUCCESSFUL=()
STEP_FAILED=()
STEP_SKIPPED=()

die() { echo -e "${RED}[ERROR]${NC} $*" >&2; return 1; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

USE_CLOUDFLARE=false
CLOUDFLARE_CONFIG_READY=false
DATABASE_DRIVER=''
DATABASE_CONFIG_READY=false
USE_SCHEDULER=false
USE_QUEUE=false
USE_HORIZON=false
CONFIGURE_DEPLOY_USER_LOGIN=false
CLIENT_PUBLIC_KEY=''
ENV_FILE_CREATED=false
ENV_UPDATED=false

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
    STEP_FAILED+=("STEP ${step_number} - ${title}")
    warn "Step failed: $title"
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
    print_step_group 'Skipped:' "${STEP_SKIPPED[@]}"
}

require_safe_inputs() {
    [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
        die 'GitHub repository must look like owner/repository'
    [[ "$APP_FOLDER" =~ ^/var/www/[A-Za-z0-9_.-]+$ ]] ||
        die 'Application folder must be a simple path under /var/www'
    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die 'Invalid domain'
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
    local key="$1" value="$2" escaped desired
    escaped="${value//\\/\\\\}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"
    escaped="${escaped//\"/\\\"}"
    desired="${key}=\"${escaped}\""

    if sudo grep -qxF "$desired" "$APP_FOLDER/shared/.env"; then
        return
    fi
    if sudo grep -qE "^${key}=" "$APP_FOLDER/shared/.env"; then
        sudo sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" "$APP_FOLDER/shared/.env"
    else
        printf '%s\n' "$desired" |
            sudo tee -a "$APP_FOLDER/shared/.env" >/dev/null
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
    if [[ "$ENV_FILE_CREATED" != true ]] && env_key_exists DB_HOST "$env_file" &&
        env_key_exists DB_PORT "$env_file" && env_key_exists DB_DATABASE "$env_file" &&
        env_key_exists DB_USERNAME "$env_file" && env_key_exists DB_PASSWORD "$env_file"; then
        read_env_value DB_HOST "$env_file" MYSQL_HOST
        read_env_value DB_PORT "$env_file" MYSQL_PORT
        read_env_value DB_DATABASE "$env_file" MYSQL_DATABASE
        read_env_value DB_USERNAME "$env_file" MYSQL_USERNAME
        read_env_value DB_PASSWORD "$env_file" MYSQL_PASSWORD
    else
        prompt_value 'MySQL host' MYSQL_HOST '127.0.0.1' || return 1
        prompt_value 'MySQL port' MYSQL_PORT '3306' || return 1
        prompt_value 'MySQL database' MYSQL_DATABASE || return 1
        prompt_value 'MySQL username' MYSQL_USERNAME || return 1
        prompt_secret 'MySQL password' MYSQL_PASSWORD || return 1
    fi

    DATABASE_CONFIG_READY=true
}
