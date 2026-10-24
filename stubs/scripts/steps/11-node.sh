#!/usr/bin/env bash
# @id: node
# @title: Install Node.js and npm
# @group: none
# @required: false
# @default: false
# @order: 20

step_node() {
    if [[ "$METATOR_OPERATION" == prepare-server ]]; then
        require_commands dpkg-query apt-get || return 1
        local missing_packages=() package
        for package in nodejs npm; do
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' ||
                missing_packages+=("$package")
        done
        if [[ "${#missing_packages[@]}" -gt 0 ]]; then
            sudo apt-get update || return 1
            sudo apt-get install -y "${missing_packages[@]}" || return 1
            require_commands node npm || return 1
        else
            ok 'Node.js and npm are unchanged and ready'
        fi
    fi

    require_commands node npm || return 1
    if [[ "$METATOR_OPERATION" == provision ]]; then
        prepare_site_npm_cache || return 1
    fi
    ok 'Node.js and npm are ready'
}

prepare_site_npm_cache() {
    local cache="$APP_FOLDER/shared/.npm" path created=false
    # Never follow a cache or shared-directory link into another site's resources.
    for path in "$APP_FOLDER" "$APP_FOLDER/shared" "$cache"; do
        if sudo test -L "$path" || { sudo test -e "$path" && ! sudo test -d "$path"; }; then
            die "Site npm cache path must be a real directory: $path"
            return 1
        fi
    done
    if ! sudo test -d "$APP_FOLDER/shared"; then
        sudo install -d -m 2770 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared" || return 1
    fi
    if ! sudo test -d "$cache"; then
        sudo install -d -m 700 -o "$DEPLOY_USER" -g "$(id -gn "$DEPLOY_USER")" "$cache" || return 1
        created=true
    fi
    # Probe as the actual deployment identity. Do not run npm cache verify here:
    # it can prune or rewrite existing cache data on otherwise unchanged reruns.
    if ! sudo -u "$DEPLOY_USER" bash -c '
        set -euo pipefail
        for path in "$1" "$1/_cacache" "$1/_logs"; do
            if [[ -e "$path" || -L "$path" ]]; then
                [[ -d "$path" && ! -L "$path" && -r "$path" && -w "$path" && -x "$path" ]]
            fi
        done
        # npm content blobs can be read-only; replacement requires writable directories.
        unusable="$(find -P "$1" -xdev \( -type l -o ! -readable -o \( -type d \( ! -writable -o ! -executable \) \) \) -print -quit)"
        [[ -z "$unusable" ]]
        probe="$(mktemp -d "$1/.metator-npm.XXXXXX")"
        trap '\''rm -rf -- "$probe"'\'' EXIT
        printf "cache readiness\n" > "$probe/entry"
        [[ "$(cat "$probe/entry")" == "cache readiness" ]]
    ' _ "$cache"; then
        die "Site npm cache is not usable by $DEPLOY_USER: $cache (check site cache permissions; do not change the shared deployment home)"
        return 1
    fi
    if [[ "$created" == true ]]; then
        ok "Site npm cache is ready: $cache"
    else
        ok "Site npm cache is unchanged and ready: $cache"
    fi
}
