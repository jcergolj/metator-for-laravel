#!/usr/bin/env bash
# shellcheck disable=SC2024,SC2094
# @id: permissions
# @title: Verify shared-file permissions
# @group: none
# @required: true
# @default: true
# @order: 60

step_permissions() {
    require_commands getfacl setfacl || {
        die 'Shared runtime ACL support is not prepared; run prepare-server first'
        return 1
    }
    local path root paths user
    local deploy_uid runtime_uid shared_gid
    deploy_uid="$(id -u "$DEPLOY_USER")" || return 1
    runtime_uid="$(id -u www-data)" || return 1
    shared_gid="$(getent group www-data | cut -d: -f3)" || return 1
    local permissions_changed=false

    # Validate every managed ancestor before creating directories or following
    # paths. Interior application symlinks are skipped by find -P below.
    for path in "$APP_FOLDER" "$APP_FOLDER/shared" \
        "$APP_FOLDER/shared/storage" "$APP_FOLDER/shared/storage/framework" \
        "$APP_FOLDER/shared/storage/framework/cache" "$APP_FOLDER/shared/storage/framework/data" \
        "$APP_FOLDER/shared/storage/framework/sessions" "$APP_FOLDER/shared/storage/framework/views" \
        "$APP_FOLDER/shared/storage/logs" "$APP_FOLDER/shared/bootstrap" \
        "$APP_FOLDER/shared/bootstrap/cache" "$APP_FOLDER/shared/database"; do
        if sudo test -L "$path" || { sudo test -e "$path" && ! sudo test -d "$path"; }; then
            die "Shared runtime directory must be a real directory: $path"
            return 1
        fi
    done
    if sudo test -L "$APP_FOLDER/shared/.env"; then
        die 'Shared .env must not be a symlink'
        return 1
    fi
    for path in "$APP_FOLDER/shared" "$APP_FOLDER/shared/storage" \
        "$APP_FOLDER/shared/storage/framework" \
        "$APP_FOLDER/shared/storage/framework/cache" "$APP_FOLDER/shared/storage/framework/data" \
        "$APP_FOLDER/shared/storage/framework/sessions" "$APP_FOLDER/shared/storage/framework/views" \
        "$APP_FOLDER/shared/storage/logs" "$APP_FOLDER/shared/bootstrap" \
        "$APP_FOLDER/shared/bootstrap/cache"; do
        if ! sudo test -d "$path"; then
            sudo install -d -m 2770 -o "$DEPLOY_USER" -g www-data "$path" || return 1
            permissions_changed=true
        fi
    done
    # Do not give shared/ a default ACL: secrets and unrelated shared resources
    # must not inherit the runtime policy.
    reconcile_shared_path "$APP_FOLDER/shared" 2770 false || return 1
    reconcile_shared_path "$APP_FOLDER/shared/bootstrap" 2770 false || return 1
    if sudo test -f "$APP_FOLDER/shared/.env"; then
        reconcile_shared_path "$APP_FOLDER/shared/.env" 640 false || return 1
    fi

    paths="$(mktemp)" || return 1
    for root in "$APP_FOLDER/shared/storage" "$APP_FOLDER/shared/bootstrap/cache" "$APP_FOLDER/shared/database"; do
        sudo test -d "$root" || continue
        # Collect first so a failed traversal is not hidden by process substitution.
        if ! sudo find -P "$root" -xdev \( -type d -o -type f \) -print0 > "$paths"; then
            rm -f "$paths"
            die "Could not inspect shared runtime paths: $root"
            return 1
        fi
        while IFS= read -r -d '' path; do
            if sudo test -d "$path"; then
                reconcile_shared_path "$path" 2770 true || { rm -f "$paths"; return 1; }
            else
                reconcile_shared_path "$path" 660 false || { rm -f "$paths"; return 1; }
            fi
            for user in "$DEPLOY_USER" www-data; do
                if ! sudo -u "$user" test -r "$path" || ! sudo -u "$user" test -w "$path" ||
                    { sudo test -d "$path" && ! sudo -u "$user" test -x "$path"; }; then
                    rm -f "$paths"
                    die "Shared runtime access failed for $user: $path"
                    return 1
                fi
            done
        done < "$paths"
        if [[ "$permissions_changed" == true ]]; then
            verify_shared_runtime_writes "$root" || { rm -f "$paths"; return 1; }
        fi
    done
    rm -f "$paths"
    if [[ "$permissions_changed" == true ]]; then
        ok 'Shared runtime permissions and inherited ACLs are ready'
    else
        ok 'Shared runtime permissions and inherited ACLs are unchanged and ready'
    fi
}

reconcile_shared_path() {
    local path="$1" mode="$2" inherit="$3" owner group acl desired
    owner="$(sudo stat -c '%u' "$path")" || return 1
    group="$(sudo stat -c '%g' "$path")" || return 1
    # Keep either legitimate creator's ownership on runtime files and directories.
    if [[ "$owner" != "$deploy_uid" && ( "$mode" == 640 || "$owner" != "$runtime_uid" ) ]]; then
        sudo chown "$DEPLOY_USER" "$path" || return 1
        permissions_changed=true
    fi
    if [[ "$group" != "$shared_gid" ]]; then
        sudo chgrp www-data "$path" || return 1
        permissions_changed=true
    fi
    case "$mode" in
        2770) desired=$'user::rwx\ngroup::rwx\nother::---' ;;
        660) desired=$'user::rw-\ngroup::rw-\nother::---' ;;
        640) desired=$'user::rw-\ngroup::r--\nother::---' ;;
    esac
    if [[ "$inherit" == true ]]; then
        desired+=$'\ndefault:user::rwx\ndefault:group::rwx\ndefault:other::---'
    fi
    acl="$(sudo getfacl -cp -- "$path")" || return 1
    if [[ "$acl" != "$desired" ]]; then
        if [[ "$inherit" != true && "$acl" == *'default:'* ]]; then
            sudo setfacl -k -- "$path" || return 1
        fi
        sudo setfacl --set="${desired//$'\n'/,}" -- "$path" || {
            die "Could not establish shared runtime ACL policy: $path"
            return 1
        }
        permissions_changed=true
    fi
    if [[ "$(sudo stat -c '%a' "$path")" != "$mode" ]]; then
        sudo chmod "$mode" "$path" || return 1
        permissions_changed=true
    fi
}

verify_shared_runtime_writes() (
    local root="$1" probe creator writer
    probe="$(sudo -u "$DEPLOY_USER" mktemp -d "$root/.metator-permissions.XXXXXX")" || {
        die "Cannot create shared runtime readiness probe: $root"
        return 1
    }
    # Only remove our unique probe, never existing runtime files or logs.
    trap 'sudo rm -rf -- "$probe"' EXIT
    sudo chmod 2770 "$probe" || return 1
    for creator in "$DEPLOY_USER" www-data; do
        if [[ "$creator" == "$DEPLOY_USER" ]]; then writer=www-data; else writer="$DEPLOY_USER"; fi
        if ! sudo -u "$creator" bash -c '
            umask 0022
            mkdir -p "$1/$2/nested" && printf "created\n" > "$1/$2/nested/log"
        ' _ "$probe" "$creator" ||
            ! sudo -u "$writer" bash -c 'printf "appended\n" >> "$1/$2/nested/log"' _ "$probe" "$creator"; then
            die "Shared runtime create/append verification failed ($creator -> $writer): $root"
            return 1
        fi
    done
)
