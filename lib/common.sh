#!/usr/bin/env bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DEPLOY_USER="deployer"
GITHUB_KEY="/home/${DEPLOY_USER}/.ssh/deployer-github"
CADDY_CERT="/etc/caddy/certs/cloudflare-wildcard.crt"
CADDY_KEY="/etc/caddy/certs/cloudflare-wildcard.key"

step_number=0

die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

prompt_value() {
    local prompt="$1" variable="$2" default="${3:-}" value
    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " value
        value="${value:-$default}"
    else
        read -r -p "$prompt: " value
    fi
    [[ -n "$value" ]] || die "$prompt is required"
    printf -v "$variable" '%s' "$value"
}

prompt_secret() {
    local prompt="$1" variable="$2" value
    read -r -s -p "$prompt: " value
    echo
    [[ -n "$value" ]] || die "$prompt is required"
    printf -v "$variable" '%s' "$value"
}

ask_yes_no() {
    local prompt="$1" default="${2:-n}" answer suffix
    if [[ "$default" =~ ^[Yy]$ ]]; then
        suffix='Y/n'
    else
        suffix='y/N'
    fi
    read -r -p "$prompt [$suffix]: " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

run_step() {
    local title="$1" description="$2" function_name="$3" answer
    step_number=$((step_number + 1))
    echo
    echo -e "${GREEN}STEP ${step_number} — ${title}${NC}"
    echo "$description"
    echo
    while true; do
        read -r -p '[c] Continue  [s] Skip  [q] Quit: ' answer
        case "$answer" in
            c|C|'') "$function_name"; return ;;
            s|S) warn "Skipped: $title"; return ;;
            q|Q) echo 'Stopped.'; exit 0 ;;
            *) echo 'Please enter c, s, or q.' ;;
        esac
    done
}

require_safe_inputs() {
    [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
        die 'GitHub repository must look like owner/repository'
    [[ "$APP_FOLDER" =~ ^/var/www/[A-Za-z0-9_.-]+$ ]] ||
        die 'Application folder must be a simple path under /var/www'
    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die 'Invalid domain'
}

detect_server_ip() {
    command -v curl >/dev/null 2>&1 || die 'curl is not installed'

    echo
    echo 'Detecting server public IP...'
    SERVER_IP="$(curl -4 -s --max-time 5 ifconfig.me ||
        curl -4 -s --max-time 5 icanhazip.com ||
        curl -4 -s --max-time 5 ipinfo.io/ip)"
    SERVER_IP="$(printf '%s' "$SERVER_IP" | tr -d '[:space:]')"
    [[ -n "$SERVER_IP" ]] || die 'Could not detect server IP'
    [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        die "Detected IP is not a valid IPv4 address: $SERVER_IP"
    ok "Detected server public IP: $SERVER_IP"
}

prompt_cloudflare() {
    USE_CLOUDFLARE=false
    if ! ask_yes_no 'Configure the Cloudflare DNS A record for this domain?' n; then
        return
    fi

    USE_CLOUDFLARE=true
    prompt_secret 'Cloudflare API token' CF_TOKEN
    prompt_value 'Cloudflare zone (for example, example.com)' CF_ZONE_NAME
    [[ "$CF_ZONE_NAME" =~ ^[A-Za-z0-9.-]+$ ]] || die 'Invalid Cloudflare zone'
}

set_env_value() {
    local key="$1" value="$2" escaped
    escaped="${value//\\/\\\\}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"
    escaped="${escaped//\"/\\\"}"

    if sudo grep -qE "^${key}=" "$APP_FOLDER/shared/.env"; then
        sudo sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" "$APP_FOLDER/shared/.env"
    else
        printf '%s\n' "${key}=\"${escaped}\"" |
            sudo tee -a "$APP_FOLDER/shared/.env" >/dev/null
    fi
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

prompt_database() {
    local choice
    echo
    echo 'Database driver:'
    echo '  1) SQLite (recommended default)'
    echo '  2) MySQL'
    read -r -p 'Choose database [1]: ' choice
    choice="${choice:-1}"

    case "$choice" in
        1)
            DATABASE_DRIVER='sqlite'
            ;;
        2)
            DATABASE_DRIVER='mysql'
            prompt_value 'MySQL host' MYSQL_HOST '127.0.0.1'
            prompt_value 'MySQL port' MYSQL_PORT '3306'
            prompt_value 'MySQL database' MYSQL_DATABASE
            prompt_value 'MySQL username' MYSQL_USERNAME
            prompt_secret 'MySQL password' MYSQL_PASSWORD
            ;;
        *)
            die 'Invalid database selection'
            ;;
    esac
}
