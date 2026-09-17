#!/usr/bin/env bash
# shellcheck disable=SC1091
# @id: prerequisites
# @title: Prepare and verify server prerequisites
# @group: none
# @required: true
# @default: true
# @order: 10

step_prerequisites() {
    if [[ "$METATOR_OPERATION" == prepare-server ]]; then
        prepare_shared_baseline || return 1
    fi

    for command in php composer git systemctl sudo sed grep cmp getent id; do
        if ! command -v "$command" >/dev/null 2>&1; then
            die "$command is not installed"
            return 1
        fi
    done
    if [[ "$DATABASE_DRIVER" == mysql ]]; then
        require_commands mariadb || return 1
        sudo systemctl is-active --quiet mariadb || {
            die 'MariaDB is not active'
            return 1
        }
    fi
    if [[ "$USE_REDIS" == true ]]; then
        require_commands redis-cli || return 1
        sudo systemctl is-active --quiet redis-server || {
            die 'Redis is not active'
            return 1
        }
    fi
    if [[ "$USE_SCHEDULER" == true ]]; then
        sudo systemctl is-active --quiet cron || {
            die 'Cron is not active'
            return 1
        }
    fi
    if [[ "$USE_QUEUE" == true ]]; then
        require_commands supervisorctl || return 1
        sudo systemctl is-active --quiet supervisor || {
            die 'Supervisor is not active; run prepare-server with workers selected'
            return 1
        }
    fi

    prepare_deploy_user
    local step_file step_id
    for step_file in "$SCRIPT_DIR"/steps/*.sh; do
        step_id="$(step_metadata "$step_file" id)"
        case "$step_id" in
            caddy) require_commands caddy || return 1 ;;
            cloudflare) require_commands curl jq || return 1 ;;
        esac
    done
    if [[ ! -S "$PHP_FPM_SOCKET" ]]; then
        die "PHP-FPM socket does not exist: $PHP_FPM_SOCKET"
        return 1
    fi
    ok 'Deployment user and required software are ready'
}

prepare_shared_baseline() {
    if [[ ! -r /etc/os-release ]] || ! grep -qE '^ID=(ubuntu|debian)$' /etc/os-release; then
        die 'Metator preparation supports Ubuntu or Debian only'
        return 1
    fi

    . /etc/os-release
    if [[ "$ID" == ubuntu ]] && [[ "${VERSION_ID:-}" != 24.04 ]]; then
        die 'Metator preparation requires Ubuntu 24.04'
        return 1
    fi

    require_commands apt-get apt-cache || return 1
    sudo apt-get update || return 1
    local shared_packages=(ca-certificates composer git curl jq unzip openssh-client software-properties-common caddy)
    if [[ "$DATABASE_DRIVER" == mysql ]]; then
        shared_packages+=(mariadb-server)
    fi
    if [[ "$USE_REDIS" == true ]]; then
        shared_packages+=(redis-server)
    fi
    if [[ "$USE_SCHEDULER" == true ]]; then
        shared_packages+=(cron)
    fi
    if [[ "$USE_QUEUE" == true ]]; then
        shared_packages+=(supervisor)
    fi
    sudo apt-get install -y "${shared_packages[@]}" || return 1
    if ! command -v caddy >/dev/null 2>&1; then
        die 'Caddy installation did not provide the caddy command; refresh generated scripts with metator:install --force and retry'
        return 1
    fi
    sudo systemctl enable --now caddy || {
        die 'Caddy service could not be enabled and started'
        return 1
    }
    if ! command -v composer >/dev/null 2>&1; then
        die 'Composer installation did not provide the composer command; refresh generated scripts with metator:install --force and retry'
        return 1
    fi

    if ! apt-cache show "php${PHP_VERSION}-fpm" >/dev/null 2>&1; then
        if ! command -v add-apt-repository >/dev/null 2>&1; then
            die 'add-apt-repository is required to install the selected PHP version'
            return 1
        fi
        sudo add-apt-repository -y ppa:ondrej/php || return 1
        sudo apt-get update || return 1
    fi
    local php_packages=(
        "php${PHP_VERSION}-cli" "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-sqlite3"
    )
    if [[ "$DATABASE_DRIVER" == mysql ]]; then
        php_packages+=("php${PHP_VERSION}-mysql")
    fi
    if [[ "$USE_REDIS" == true ]]; then
        php_packages+=("php${PHP_VERSION}-redis")
    fi
    sudo apt-get install -y "${php_packages[@]}" || return 1

    sudo systemctl enable --now "php${PHP_VERSION}-fpm" || return 1
    if [[ "$DATABASE_DRIVER" == mysql ]]; then
        sudo systemctl enable --now mariadb || return 1
    fi
    if [[ "$USE_REDIS" == true ]]; then
        sudo systemctl enable --now redis-server || return 1
    fi
    if [[ "$USE_SCHEDULER" == true ]]; then
        sudo systemctl enable --now cron || return 1
    fi
    if [[ "$USE_QUEUE" == true ]]; then
        sudo systemctl enable --now supervisor || return 1
    fi
    ok "Shared PHP ${PHP_VERSION} baseline is ready"
}
