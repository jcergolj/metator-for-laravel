#!/usr/bin/env bash

step_caddy() {
    [[ -f "$CADDY_CERT" ]] || die "Missing certificate: $CADDY_CERT"
    [[ -f "$CADDY_KEY" ]] || die "Missing private key: $CADDY_KEY"
    sudo install -d -m 755 -o root -g root /etc/caddy/sites-enabled
    if ! sudo grep -Fq 'import /etc/caddy/sites-enabled/*.caddy' /etc/caddy/Caddyfile; then
        printf '\nimport /etc/caddy/sites-enabled/*.caddy\n' |
            sudo tee -a /etc/caddy/Caddyfile >/dev/null
    fi

    local temporary backup=''
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
    if sudo test -f "$CADDY_SITE"; then
        backup="${CADDY_SITE}.bak.$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$CADDY_SITE" "$backup"
    fi
    sudo install -m 644 -o root -g root "$temporary" "$CADDY_SITE"
    rm -f "$temporary"
    if ! sudo caddy validate --config /etc/caddy/Caddyfile; then
        [[ -n "$backup" ]] && sudo cp -a "$backup" "$CADDY_SITE" || sudo rm -f "$CADDY_SITE"
        die 'Caddy validation failed; the previous site configuration was restored'
    fi
    sudo systemctl reload caddy
    ok 'Caddy configuration is valid and active'
}
