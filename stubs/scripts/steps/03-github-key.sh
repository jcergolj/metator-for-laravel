#!/usr/bin/env bash

step_github_key() {
    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh" || return 1
    local ssh_config="/home/${DEPLOY_USER}/.ssh/config"
    local temporary existing merged
    temporary="$(mktemp)" || return 1
    existing="$(mktemp)" || { rm -f "$temporary"; return 1; }
    if sudo test -e "$ssh_config"; then
        # Compare markers literally: dots in app names are not regex wildcards.
        # Refuse an alias already owned by another block (SSH ignores casing).
        if ! sudo awk -v marker="$GITHUB_CONFIG_MARKER" -v alias="$GITHUB_ALIAS" \
            -v repository="$GITHUB_REPOSITORY" '
            $0 == "# BEGIN " marker { if (inside) exit 1; inside = 1; next }
            $0 == "# END " marker { if (!inside) exit 1; inside = 0; next }
            inside {
                if ($0 ~ /^# Repository: / && $0 != "# Repository: " repository) exit 1
                next
            }
            {
                line = $0
                gsub(/=/, " ", line)
                count = split(line, fields, /[ \t]+/)
                start = (fields[1] == "" ? 2 : 1)
                if (tolower(fields[start]) == "host") {
                    for (i = start + 1; i <= count; i++) {
                        if (fields[i] ~ /^#/) break
                        if (tolower(fields[i]) == tolower(alias)) exit 1
                    }
                }
                print
            }
            END { if (inside) exit 1 }
        ' "$ssh_config" > "$existing"; then
            rm -f "$temporary" "$existing"
            die "SSH alias collision, repository mismatch, or invalid managed block in $ssh_config; choose a unique Git SSH deployer name"
            return 1
        fi
    fi
    if ! sudo test -e "$GITHUB_KEY"; then
        if sudo test -e "${GITHUB_KEY}.pub"; then
            rm -f "$temporary" "$existing"
            die "Public key already exists without its private key: ${GITHUB_KEY}.pub"
            return 1
        fi
        sudo -u "$DEPLOY_USER" ssh-keygen -t ed25519 -f "$GITHUB_KEY" \
            -C "${APP_NAME} production deployer key" -N '' || {
                rm -f "$temporary" "$existing"
                return 1
            }
        warn "Add this app-specific key to the ${GITHUB_REPOSITORY} GitHub repository before continuing:"
        sudo -u "$DEPLOY_USER" cat "${GITHUB_KEY}.pub"
        read -r -p 'Press Enter after adding the key to GitHub: '
    fi
    # Specific hosts precede wildcard defaults; retain global options above them.
    cat > "$temporary" <<EOF
# BEGIN ${GITHUB_CONFIG_MARKER}
# Repository: ${GITHUB_REPOSITORY}
Host ${GITHUB_ALIAS}
    HostName github.com
    User git
    IdentityFile ${GITHUB_KEY}
    IdentitiesOnly yes
# END ${GITHUB_CONFIG_MARKER}
EOF
    merged="$(mktemp)" || { rm -f "$temporary" "$existing"; return 1; }
    if ! awk -v block="$temporary" '
        {
            lines[NR] = $0
            line = tolower($0)
            if (line ~ /^[ \t]*(host|match)[ \t=]/) scoped = 1
            if (!scoped && line !~ /^[ \t]*(#|$)/) global_end = NR
        }
        END {
            for (i = 1; i <= global_end; i++) print lines[i]
            while ((getline line < block) > 0) print line
            close(block)
            for (i = global_end + 1; i <= NR; i++) print lines[i]
        }
    ' "$existing" > "$merged"; then
        rm -f "$temporary" "$existing" "$merged"
        return 1
    fi
    rm -f "$existing" "$temporary"
    temporary="$merged"
    if ! sudo cmp -s "$temporary" "$ssh_config"; then
        sudo install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$temporary" "$ssh_config" || {
            rm -f "$temporary"
            return 1
        }
    fi
    rm -f "$temporary"
    sudo chmod 600 "$ssh_config"
    sudo chmod 600 "$GITHUB_KEY"
    sudo chown "$DEPLOY_USER:$DEPLOY_USER" "$ssh_config" "$GITHUB_KEY"

    if ! sudo -u "$DEPLOY_USER" git ls-remote "$GITHUB_URL" HEAD >/dev/null; then
        die 'GitHub access failed'
        return 1
    fi
    ok "App-specific GitHub key can read $GITHUB_REPOSITORY"
}
