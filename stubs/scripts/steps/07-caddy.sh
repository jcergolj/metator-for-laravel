#!/usr/bin/env bash

step_caddy() {
    if ! sudo test -f "$CADDY_CERT"; then
        die "Missing certificate: $CADDY_CERT"
        return 1
    fi
    if ! sudo test -f "$CADDY_KEY"; then
        die "Missing private key: $CADDY_KEY"
        return 1
    fi
    sudo install -d -m 755 -o root -g root /etc/caddy/sites-enabled
    local caddyfile_changed=false caddyfile_backup='' caddyfile_existed=false
    if ! sudo grep -qxE '[[:space:]]*import /etc/caddy/sites-enabled/\*\.caddy[[:space:]]*' /etc/caddy/Caddyfile; then
        caddyfile_backup="$(mktemp)" || return 1
        if sudo test -e /etc/caddy/Caddyfile; then
            caddyfile_existed=true
            sudo cp -p /etc/caddy/Caddyfile "$caddyfile_backup" || { rm -f "$caddyfile_backup"; return 1; }
        fi
        printf '\nimport /etc/caddy/sites-enabled/*.caddy\n' |
            sudo tee -a /etc/caddy/Caddyfile >/dev/null || { rm -f "$caddyfile_backup"; return 1; }
        caddyfile_changed=true
    fi

    local temporary backup='' changed=false
    temporary="$(mktemp)"
    cat > "$temporary" <<EOF
${DOMAIN} {
    root * ${APP_FOLDER}/current/public
    php_fastcgi unix/${PHP_FPM_SOCKET}
    file_server
    encode zstd gzip
    tls ${CADDY_CERT} ${CADDY_KEY}
}
EOF
    if [[ "$caddyfile_changed" == true ]] || ! sudo cmp -s "$temporary" "$CADDY_SITE"; then
        changed=true
    fi
    if [[ "$changed" != true ]]; then
        rm -f "$temporary"
        ok 'Caddy configuration is already current'

        return
    fi
    if sudo test -f "$CADDY_SITE"; then
        warn "Updating existing Caddy site file at $CADDY_SITE"
    else
        warn "Creating Caddy site file at $CADDY_SITE"
    fi
    if sudo test -f "$CADDY_SITE"; then
        backup="${CADDY_SITE}.bak.$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$CADDY_SITE" "$backup"
    fi
    sudo install -m 644 -o root -g root "$temporary" "$CADDY_SITE"
    rm -f "$temporary"
    if ! sudo caddy validate --config /etc/caddy/Caddyfile; then
        [[ -n "$backup" ]] && sudo cp -a "$backup" "$CADDY_SITE" || sudo rm -f "$CADDY_SITE"
        if [[ "$caddyfile_changed" == true ]]; then
            if [[ "$caddyfile_existed" == true ]]; then
                sudo cp -p "$caddyfile_backup" /etc/caddy/Caddyfile
            else
                sudo rm -f /etc/caddy/Caddyfile
            fi
            rm -f "$caddyfile_backup"
        fi
        die 'Caddy validation failed; the previous site and shared configurations were restored'
        return 1
    fi
    [[ -z "$caddyfile_backup" ]] || rm -f "$caddyfile_backup"
    warn "Review $CADDY_SITE before continuing."
    read -r -p 'Press Enter to confirm the Caddy config review and continue: '
    sudo systemctl reload caddy
    ok 'Caddy configuration is valid and active'
}
