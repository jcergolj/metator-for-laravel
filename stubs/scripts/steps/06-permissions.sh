#!/usr/bin/env bash
# @id: permissions
# @title: Verify shared-file permissions
# @group: none
# @required: true
# @default: true
# @order: 60

step_permissions() {
    local shared_root="$APP_FOLDER/shared"
    sudo install -d -m 2770 \
        "$APP_FOLDER/shared/storage/framework/cache" \
        "$APP_FOLDER/shared/storage/framework/data" \
        "$APP_FOLDER/shared/storage/framework/sessions" \
        "$APP_FOLDER/shared/storage/framework/views" \
        "$APP_FOLDER/shared/storage/logs" \
        "$APP_FOLDER/shared/bootstrap/cache"
    reconcile_shared_permissions "$shared_root" || return 1
    ok 'Shared files are restricted to deployer and www-data'
}

reconcile_shared_permissions() {
    local root="$1" path mode owner_group
    while IFS= read -r -d '' path; do
        if [[ -d "$path" ]]; then
            mode=2770
        elif [[ "$path" == "$root/.env" ]]; then
            mode=640
        else
            mode=660
        fi
        owner_group="$(stat -c '%U:%G' "$path")" || return 1
        if [[ "$owner_group" != "$DEPLOY_USER:www-data" ]]; then
            sudo chown "$DEPLOY_USER:www-data" "$path" || return 1
        fi
        if [[ "$(stat -c '%a' "$path")" != "$mode" ]]; then
            sudo chmod "$mode" "$path" || return 1
        fi
    done < <(find "$root" -print0)
}
