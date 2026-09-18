#!/usr/bin/env bash
# @id: caddy
# @title: Configure Caddy
# @group: web-server
# @required: false
# @default: true
# @order: 70

step_caddy() {
    local metadata existing_domain existing_site_id metadata_app_folder
    for metadata in /var/www/*/.metator-site; do
        sudo test -f "$metadata" || continue
        existing_domain="$(sudo sed -nE 's/^domain[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$/\1/p' "$metadata" | sed -n '1p')"
        existing_site_id="$(sudo sed -nE 's/^site_id[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$/\1/p' "$metadata" | sed -n '1p')"
        metadata_app_folder="$(dirname "$metadata")"
        if [[ "$existing_domain" == "$DOMAIN" && "$existing_site_id" != "$SITE_ID" ]]; then
            die "Domain is already assigned to site $existing_site_id: $DOMAIN"
            return 1
        fi
        if [[ "$existing_site_id" == "$SITE_ID" && "$metadata_app_folder" != "$APP_FOLDER" ]]; then
            die "Site ID is already assigned to another application folder: $existing_site_id"
            return 1
        fi
    done

    local site_marker="# Managed by Metator: site_id=${SITE_ID} domain=${DOMAIN}"
    if sudo test -e "$CADDY_SITE" &&
        ! sudo grep -Fqx "$site_marker" "$CADDY_SITE"; then
        die "Caddy site file is not owned by this site: $CADDY_SITE"
        return 1
    fi

    local temporary candidate_dir candidate_caddy candidate_sites current_caddy
    temporary="$(mktemp -d)"
    candidate_dir="$temporary/caddy"
    candidate_sites="$candidate_dir/sites-enabled"
    candidate_caddy="$candidate_dir/Caddyfile"
    current_caddy=/etc/caddy/Caddyfile
    mkdir -p "$candidate_sites"
    if sudo test -f "$current_caddy"; then
        sudo cp -p "$current_caddy" "$candidate_caddy" || { rm -rf "$temporary"; return 1; }
    else
        : > "$candidate_caddy"
    fi
    for metadata in /etc/caddy/sites-enabled/*.caddy; do
        sudo test -f "$metadata" || continue
        sudo cp -p "$metadata" "$candidate_sites/$(basename "$metadata")" || { rm -rf "$temporary"; return 1; }
    done
    cat > "$candidate_sites/$(basename "$CADDY_SITE")" <<EOF
${site_marker}
${DOMAIN} {
    root * ${APP_FOLDER}/current/public
    php_fastcgi unix/${PHP_FPM_SOCKET}
    file_server
    encode zstd gzip
}
EOF

    if sudo grep -qE '^[[:space:]]*import[[:space:]]+/etc/caddy/sites-enabled/\*\.caddy[[:space:]]*$' "$candidate_caddy"; then
        if ! sudo sed -i "s#^[[:space:]]*import[[:space:]]*/etc/caddy/sites-enabled/\\*\\.caddy[[:space:]]*\$#import ${candidate_sites}/*.caddy#" "$candidate_caddy"; then
            rm -rf "$temporary"
            die 'Could not prepare Caddy candidate imports; no live configuration was changed'
            return 1
        fi
    else
        printf '\nimport %s/*.caddy\n' "$candidate_sites" >> "$candidate_caddy"
    fi
    if ! sudo caddy validate --config "$candidate_caddy"; then
        rm -rf "$temporary"
        die 'Caddy validation failed; no live configuration was changed'
        return 1
    fi

    local changed=false main_backup='' site_backup=''
    if ! sudo test -f "$CADDY_SITE" || ! sudo cmp -s "$candidate_sites/$(basename "$CADDY_SITE")" "$CADDY_SITE"; then
        changed=true
    fi
    if ! sudo grep -qE '^[[:space:]]*import[[:space:]]+/etc/caddy/sites-enabled/\*\.caddy[[:space:]]*$' "$current_caddy" 2>/dev/null; then
        changed=true
    fi
    if [[ "$changed" != true ]]; then
        if ! sudo systemctl is-active --quiet caddy; then
            rm -rf "$temporary"
            die 'Caddy configuration is unchanged but service readiness could not be verified; restore the Caddy service before retrying'
            return 1
        fi
        rm -rf "$temporary"
        record_site_domain || return 1
        ok 'Caddy configuration is unchanged and the service is active'
        return
    fi

    if sudo test -f "$current_caddy"; then main_backup="$temporary/Caddyfile.backup"; sudo cp -p "$current_caddy" "$main_backup"; fi
    if sudo test -f "$CADDY_SITE"; then site_backup="$temporary/site.backup"; sudo cp -p "$CADDY_SITE" "$site_backup"; fi
    sudo install -d -m 755 -o root -g root /etc/caddy/sites-enabled
    sudo install -m 644 -o root -g root "$candidate_sites/$(basename "$CADDY_SITE")" "$CADDY_SITE"
    if ! sudo grep -qE '^[[:space:]]*import[[:space:]]+/etc/caddy/sites-enabled/\*\.caddy[[:space:]]*$' "$current_caddy" 2>/dev/null; then
        printf '\nimport /etc/caddy/sites-enabled/*.caddy\n' | sudo tee -a "$current_caddy" >/dev/null
    fi
    if ! sudo systemctl reload caddy; then
        if [[ -n "$main_backup" ]]; then sudo cp -p "$main_backup" "$current_caddy"; else sudo rm -f "$current_caddy"; fi
        if [[ -n "$site_backup" ]]; then sudo cp -p "$site_backup" "$CADDY_SITE"; else sudo rm -f "$CADDY_SITE"; fi
        rm -rf "$temporary"
        die 'Caddy reload failed; the previous site and shared configurations were restored'
        return 1
    fi
    record_site_domain || { rm -rf "$temporary"; return 1; }
    rm -rf "$temporary"
    ok 'Caddy configuration is valid and active with automatic HTTPS'
}
