#!/usr/bin/env bash
set -Eeuo pipefail

: "${HCLOUD_TOKEN:?Set HCLOUD_TOKEN to destroy the disposable Hetzner acceptance server}"

target_id="${1:?Usage: destroy.sh <server-id>}"
STATE_DIR="${METATOR_ACCEPTANCE_STATE_DIR:-${HOME:?HOME is required}/.local/state/metator-acceptance/hetzner}"
[[ "$target_id" =~ ^[0-9]+$ ]] || { printf 'Invalid Hetzner server ID: %s\n' "$target_id" >&2; exit 1; }
state_file="$STATE_DIR/$target_id"
[[ -f "$state_file" ]] || { printf 'Acceptance target state not found: %s\n' "$state_file" >&2; exit 1; }

server_id="$(basename "$state_file")"
mapfile -t state < "$state_file"
identity="${state[0]:-}"
ssh_key_id="${state[1]:-}"
response_file="$(mktemp)"
http_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request DELETE \
    --header "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/servers/$server_id")"
if [[ "$http_status" != 200 && "$http_status" != 202 && "$http_status" != 404 ]]; then
    jq -r '.error.message // "Hetzner server deletion failed"' "$response_file" >&2
    rm -f "$response_file"
    exit 1
fi
if [[ "$http_status" == 200 || "$http_status" == 202 ]]; then
    deleted=false
    for _ in {1..60}; do
        status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
            --header "Authorization: Bearer $HCLOUD_TOKEN" \
            "https://api.hetzner.cloud/v1/servers/$server_id")"
        if [[ "$status" == 404 ]]; then
            deleted=true
            break
        fi
        sleep 2
    done
    [[ "$deleted" == true ]] || { printf 'Hetzner server deletion did not complete: %s\n' "$server_id" >&2; exit 1; }
fi
rm -f "$response_file"
if [[ -n "$ssh_key_id" ]]; then
    key_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
        --request DELETE \
        --header "Authorization: Bearer $HCLOUD_TOKEN" \
        "https://api.hetzner.cloud/v1/ssh_keys/$ssh_key_id")"
    if [[ "$key_status" != 200 && "$key_status" != 202 && "$key_status" != 204 && "$key_status" != 404 ]]; then
        jq -r '.error.message // "Hetzner SSH key deletion failed"' "$response_file" >&2
        exit 1
    fi
    if [[ "$key_status" != 404 ]]; then
        key_deleted=false
        for _ in {1..60}; do
            key_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
                --header "Authorization: Bearer $HCLOUD_TOKEN" \
                "https://api.hetzner.cloud/v1/ssh_keys/$ssh_key_id")"
            if [[ "$key_status" == 404 ]]; then
                key_deleted=true
                break
            fi
            sleep 2
        done
        [[ "$key_deleted" == true ]] || { printf 'Hetzner SSH key deletion did not complete: %s\n' "$ssh_key_id" >&2; exit 1; }
    fi
fi
rm -f "$response_file" "$state_file" "$identity" "${identity}.pub"
rmdir "$(dirname "$state_file")" 2>/dev/null || true
