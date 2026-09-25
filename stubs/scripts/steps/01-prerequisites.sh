#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
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
    local os_release_file="${METATOR_OS_RELEASE_FILE:-/etc/os-release}"
    if [[ ! -r "$os_release_file" ]] || ! grep -qE '^ID=(ubuntu|debian)$' "$os_release_file"; then
        die 'Metator preparation supports Ubuntu or Debian only'
        return 1
    fi

    . "$os_release_file"
    if [[ "$ID" == ubuntu ]] && [[ "${VERSION_ID:-}" != 24.04 && "${VERSION_ID:-}" != 26.04 ]]; then
        die 'Metator preparation requires Ubuntu 24.04 or 26.04'
        return 1
    fi

    require_commands apt-get apt-cache dpkg-query || return 1
    local shared_packages=(ca-certificates composer git curl jq unzip openssh-client software-properties-common caddy)
    [[ "$DATABASE_DRIVER" == sqlite ]] && shared_packages+=(sqlite3)
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
    local missing_packages=() missing_command_packages=() package required_command
    for package in "${shared_packages[@]}"; do
        dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' ||
            missing_packages+=("$package")
    done
    for required_command in composer git curl jq unzip caddy; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            if dpkg-query -W -f='${Status}' "$required_command" 2>/dev/null | grep -qx 'install ok installed'; then
                missing_command_packages+=("$required_command")
            elif [[ " ${missing_packages[*]} " != *" $required_command "* ]]; then
                missing_packages+=("$required_command")
            fi
        fi
    done
    if [[ "${#missing_packages[@]}" -gt 0 || "${#missing_command_packages[@]}" -gt 0 ]]; then
        sudo apt-get update || return 1
    fi
    if [[ "${#missing_packages[@]}" -gt 0 ]]; then
        sudo apt-get install -y "${missing_packages[@]}" || return 1
    fi
    if [[ "${#missing_command_packages[@]}" -gt 0 ]]; then
        sudo apt-get install --reinstall -y "${missing_command_packages[@]}" || return 1
    fi
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

    local php_packages=(
        "php${PHP_VERSION}-cli" "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-sqlite3"
    )
    if [[ "$DATABASE_DRIVER" == mysql ]]; then
        php_packages+=("php${PHP_VERSION}-mysql")
    fi
    if [[ "$USE_REDIS" == true ]]; then
        php_packages+=("php${PHP_VERSION}-redis")
    fi

    local missing_php_packages=()
    for package in "${php_packages[@]}"; do
        dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' ||
            missing_php_packages+=("$package")
    done
    if [[ "${#missing_php_packages[@]}" -gt 0 ]] && ! apt-cache show "php${PHP_VERSION}-fpm" >/dev/null 2>&1; then
        configure_php_package_source "$os_release_file" || return 1
    fi
    if [[ "${#missing_php_packages[@]}" -gt 0 ]]; then
        sudo apt-get install -y "${missing_php_packages[@]}" || return 1
    fi

    local required_services=(caddy "php${PHP_VERSION}-fpm")
    [[ "$DATABASE_DRIVER" == mysql ]] && required_services+=(mariadb)
    [[ "$USE_REDIS" == true ]] && required_services+=(redis-server)
    [[ "$USE_SCHEDULER" == true ]] && required_services+=(cron)
    [[ "$USE_QUEUE" == true ]] && required_services+=(supervisor)

    local service active enabled
    for service in "${required_services[@]}"; do
        active=false
        enabled=false
        sudo systemctl is-active --quiet "$service" && active=true
        sudo systemctl is-enabled --quiet "$service" && enabled=true
        if [[ "$active" != true || "$enabled" != true ]]; then
            sudo systemctl enable --now "$service" || return 1
        fi
        sudo systemctl is-active --quiet "$service" || {
            die "$service is not active after preparation"
            return 1
        }
    done
    if [[ "${#missing_packages[@]}" -eq 0 && "${#missing_command_packages[@]}" -eq 0 && "${#missing_php_packages[@]}" -eq 0 ]]; then
        ok "Shared PHP ${PHP_VERSION} baseline is unchanged and ready"
    else
        ok "Shared PHP ${PHP_VERSION} baseline is ready"
    fi
}

configure_php_package_source() {
    local os_release_file="$1" id version_id version_codename
    . "$os_release_file"
    id="$ID"
    version_id="${VERSION_ID:-}"
    version_codename="${VERSION_CODENAME:-}"

    if [[ "$id" == ubuntu && "$version_id" == 26.04 && "$PHP_VERSION" == 8.4 ]]; then
        configure_sury_php_repository "$version_codename" || return 1
    else
        if ! command -v add-apt-repository >/dev/null 2>&1; then
            die 'add-apt-repository is required to install the selected PHP version'
            return 1
        fi
        sudo add-apt-repository -y ppa:ondrej/php || return 1
    fi

    sudo apt-get update
}

configure_sury_php_repository() {
    local codename="$1"
    if [[ "$codename" != resolute ]]; then
        die "Unexpected Ubuntu 26.04 codename for the Sury PHP repository: ${codename:-unset}"
        return 1
    fi

    require_commands curl dpkg || return 1

    local source_file="${METATOR_PHP_SURY_SOURCE_FILE:-/etc/apt/sources.list.d/metator-php-sury.list}"
    local keyring="${METATOR_PHP_SURY_KEYRING_PATH:-/usr/share/keyrings/debsuryorg-archive-keyring.gpg}"
    local source_entry="deb [signed-by=${keyring}] https://packages.sury.org/php/ ${codename} main"
    local candidate keyring_directory keyring_package

    candidate="$(mktemp)" || return 1
    printf '%s\n' "$source_entry" > "$candidate"
    if sudo test -e "$source_file" && ! sudo cmp -s "$candidate" "$source_file"; then
        rm -f "$candidate"
        die "Existing PHP package source is not owned by Metator or does not match: $source_file"
        return 1
    fi

    if ! sudo test -f "$keyring"; then
        keyring_directory="$(mktemp -d)" || { rm -f "$candidate"; return 1; }
        keyring_package="$keyring_directory/debsuryorg-archive-keyring.deb"
        if ! curl --fail --silent --show-error --location \
            --output "$keyring_package" \
            'https://packages.sury.org/debsuryorg-archive-keyring.deb'; then
            rm -rf "$keyring_directory" "$candidate"
            die 'Could not download the Sury PHP archive keyring package'
            return 1
        fi
        if ! sudo dpkg -i "$keyring_package"; then
            rm -rf "$keyring_directory" "$candidate"
            return 1
        fi
        rm -rf "$keyring_directory"
    fi

    if ! sudo test -e "$source_file"; then
        if ! sudo install -m 644 -o root -g root "$candidate" "$source_file"; then
            rm -f "$candidate"
            return 1
        fi
    fi
    rm -f "$candidate"
}
