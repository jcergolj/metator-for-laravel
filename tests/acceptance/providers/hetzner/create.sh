#!/usr/bin/env bash
set -Eeuo pipefail

: "${HCLOUD_TOKEN:?Set HCLOUD_TOKEN for the disposable Hetzner acceptance server}"
: "${METATOR_ACCEPTANCE_UBUNTU_RELEASE:?The release-gate runner must select an Ubuntu release}"

[[ "$METATOR_ACCEPTANCE_UBUNTU_RELEASE" == 24.04 ]] || {
    printf 'This Redis acceptance provider currently supports Ubuntu 24.04 only\n' >&2
    exit 1
}

STATE_DIR="${METATOR_ACCEPTANCE_STATE_DIR:-${HOME:?HOME is required}/.local/state/metator-acceptance/hetzner}"
mkdir -p "$STATE_DIR" "$HOME/.ssh"
chmod 700 "$STATE_DIR" "$HOME/.ssh"

run_id="$(date -u +%Y%m%d%H%M%S)-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
name="metator-redis-${run_id}"
identity="$HOME/.ssh/id_ed25519"
response_file="$(mktemp)"
server_id=''
ssh_key_id=''
state_file=''
identity_created=false
cleanup_on_error() {
    local status=$?
    if [[ -n "$server_id" ]]; then
        curl --silent --show-error --request DELETE \
            --header "Authorization: Bearer $HCLOUD_TOKEN" \
            "https://api.hetzner.cloud/v1/servers/$server_id" >/dev/null || true
    fi
    if [[ -n "$ssh_key_id" ]]; then
        curl --silent --show-error --request DELETE \
            --header "Authorization: Bearer $HCLOUD_TOKEN" \
            "https://api.hetzner.cloud/v1/ssh_keys/$ssh_key_id" >/dev/null || true
    fi
    rm -f "$response_file"
    if [[ "$identity_created" == true ]]; then
        rm -f "$identity" "$identity.pub"
    fi
    [[ -z "$state_file" ]] || rm -f "$state_file"
    exit "$status"
}
trap cleanup_on_error EXIT INT TERM

if [[ -e "$identity" || -e "$identity.pub" ]]; then
    printf 'Refusing to overwrite an existing SSH key: %s\n' "$identity" >&2
    exit 1
fi
ssh-keygen -q -t ed25519 -N '' -C "$name" -f "$identity"
identity_created=true
chmod 600 "$identity"
chmod 644 "$identity.pub"

public_key="$(<"$identity.pub")"
key_request="$(jq -n --arg name "$name" --arg public_key "$public_key" \
    '{name:$name, public_key:$public_key}')"
http_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $HCLOUD_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "$key_request" \
    https://api.hetzner.cloud/v1/ssh_keys)"
if [[ "$http_status" != 201 ]]; then
    jq -r '.error.message // "Hetzner SSH key registration failed"' "$response_file" >&2
    exit 1
fi
ssh_key_id="$(jq -er '.ssh_key.id' "$response_file")"

user_data="$(printf '%s\n' \
    '#cloud-config' \
    'runcmd:' \
    '  - [bash, -lc, "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y ca-certificates curl git jq software-properties-common unzip; add-apt-repository -y ppa:ondrej/php; apt-get update; apt-get install -y composer php8.5-cli php8.5-fpm php8.5-bcmath php8.5-curl php8.5-intl php8.5-mbstring php8.5-redis php8.5-sqlite3 php8.5-xml php8.5-zip; update-alternatives --install /usr/bin/php php /usr/bin/php8.5 85; update-alternatives --set php /usr/bin/php8.5; systemctl enable --now php8.5-fpm"]')"

request="$(jq -n \
    --arg name "$name" \
    --arg user_data "$user_data" \
    --arg release "$METATOR_ACCEPTANCE_UBUNTU_RELEASE" \
    --argjson ssh_key_id "$ssh_key_id" \
    '{name:$name, server_type:"cx23", location:"nbg1", image:("ubuntu-"+$release), ssh_keys:[$ssh_key_id], user_data:$user_data, labels:{purpose:"metator-acceptance", scenario:"redis-site-isolation"}}')"

http_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $HCLOUD_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "$request" \
    https://api.hetzner.cloud/v1/servers)"
if [[ "$http_status" != 201 ]]; then
    jq -r '.error.message // "Hetzner server creation failed"' "$response_file" >&2
    exit 1
fi

server_id="$(jq -er '.server.id' "$response_file")"
host="$(jq -er '.server.public_net.ipv4.ip' "$response_file")"
[[ "$host" != null && "$host" != '' ]]
rm -f "$response_file"
response_file="$(mktemp)"
state_file="$STATE_DIR/$server_id"
printf '%s\n%s\n' "$identity" "$ssh_key_id" > "$state_file"
chmod 600 "$state_file"

ssh_options=(-i "$identity" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new
    -o "UserKnownHostsFile=$HOME/.ssh/known_hosts" -o GlobalKnownHostsFile=/dev/null)
ready=false
user=''
bootstrap_log="$HOME/hetzner-bootstrap-ssh.log"
max_attempts="${METATOR_ACCEPTANCE_BOOTSTRAP_ATTEMPTS:-60}"
for ((attempt=1; attempt<=max_attempts; attempt++)); do
    for candidate in ubuntu root; do
        if ssh "${ssh_options[@]}" "$candidate@$host" true >/dev/null 2>&1; then
            user="$candidate"
            if ! ssh "${ssh_options[@]}" "$user@$host" 'cloud-init status --wait >/dev/null'; then
                ssh "${ssh_options[@]}" "$user@$host" 'cloud-init status --long; tail -n 100 /var/log/cloud-init-output.log' >&2 || true
                printf 'Cloud-init failed on disposable target %s\n' "$host" >&2
                exit 1
            fi
            if ssh "${ssh_options[@]}" "$user@$host" 'command -v php && command -v composer && command -v git && command -v sudo && command -v systemctl' >/dev/null 2>&1; then
                ready=true
                break 2
            fi
            ssh "${ssh_options[@]}" "$user@$host" 'cloud-init status --long; tail -n 100 /var/log/cloud-init-output.log' >&2 || true
            printf 'Cloud-init finished without the required acceptance baseline\n' >&2
            exit 1
        fi
    done
    if (( attempt % 6 == 0 )); then
        printf 'Waiting for SSH/cloud-init on acceptance target %s (attempt %s/%s)\n' "$host" "$attempt" "$max_attempts" >&2
        for candidate in ubuntu root; do
            ssh -vv "${ssh_options[@]}" "$candidate@$host" true >/dev/null 2>>"$bootstrap_log" || true
        done
    fi
    sleep 10
done
if [[ "$ready" != true ]]; then
    printf 'Disposable Ubuntu %s target did not become ready: %s (server %s)\n' \
        "$METATOR_ACCEPTANCE_UBUNTU_RELEASE" "$host" "$server_id" >&2
    if [[ -f "$bootstrap_log" ]]; then
        printf 'SSH diagnostics: %s\n' "$bootstrap_log" >&2
        tail -n 40 "$bootstrap_log" >&2
    fi
    exit 1
fi

rm -f "$response_file"
trap - EXIT INT TERM
printf 'host=%s\nuser=%s\nidentity=%s\ntarget_id=%s\n' "$host" "$user" "$identity" "$server_id"
