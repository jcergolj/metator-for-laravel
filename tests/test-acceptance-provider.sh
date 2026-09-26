#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home"

cat > "$TEST_DIR/bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -f) key_path="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf '%s\n' 'private test key' > "$key_path"
printf '%s\n' 'ssh-ed25519 AAAATEST fixture' > "$key_path.pub"
EOF
cat > "$TEST_DIR/bin/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
method=GET
output=''
request_data=''
url=''
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --request) method="$2"; shift 2 ;;
        --output) output="$2"; shift 2 ;;
        --data) request_data="$2"; shift 2 ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
printf '%s %s\n' "$method" "$url" >> "$TEST_CURL_CALLS"
if [[ "$method" == POST ]]; then
    if [[ "$url" == */ssh_keys ]]; then
        printf '%s\n' '{"ssh_key":{"id":9876}}' > "$output"
    else
        printf '%s\n' "$request_data" > "$TEST_CREATE_REQUEST"
        printf '%s\n' '{"server":{"id":43210,"public_net":{"ipv4":{"ip":"192.0.2.10"}}}}' > "$output"
    fi
    printf '201'
elif [[ "$method" == DELETE ]]; then
    printf '%s\n' '{}' > "$output"
    printf '202'
elif [[ "$method" == GET && "$url" == */ssh_keys/* ]]; then
    key_gets="$(<"$TEST_SSH_KEY_GETS")"
    key_gets=$((key_gets + 1))
    printf '%s' "$key_gets" > "$TEST_SSH_KEY_GETS"
    if [[ "$key_gets" -eq 1 ]]; then
        printf '%s\n' '{"ssh_key":{"id":9876}}' > "$output"
        printf '200'
    else
        printf '%s\n' '{"error":{"message":"not found"}}' > "$output"
        printf '404'
    fi
else
    printf '%s\n' '{"error":{"message":"not found"}}' > "$output"
    printf '404'
fi
EOF
chmod +x "$TEST_DIR/bin/ssh-keygen" "$TEST_DIR/bin/ssh" "$TEST_DIR/bin/curl"

export PATH="$TEST_DIR/bin:$PATH"
export HOME="$TEST_DIR/home"
export HCLOUD_TOKEN='test-token'
export METATOR_ACCEPTANCE_UBUNTU_RELEASE=24.04
export TEST_CURL_CALLS="$TEST_DIR/curl-calls"
export TEST_CREATE_REQUEST="$TEST_DIR/create-request.json"
export TEST_SSH_KEY_GETS="$TEST_DIR/ssh-key-gets"
touch "$TEST_CURL_CALLS"
touch "$TEST_SSH_KEY_GETS"

provider_output="$("$ROOT_DIR/tests/acceptance/providers/hetzner/create.sh")"
[[ "$provider_output" == *'host=192.0.2.10'* ]]
[[ "$provider_output" == *'user=ubuntu'* ]]
[[ "$provider_output" == *'target_id=43210'* ]]
[[ -f "$HOME/.ssh/id_ed25519" && -f "$HOME/.ssh/id_ed25519.pub" ]]
request="$(<"$TEST_CREATE_REQUEST")"
[[ "$(jq -r '.server_type' <<< "$request")" == cx23 ]]
[[ "$(jq -r '.location' <<< "$request")" == nbg1 ]]
[[ "$(jq -r '.image' <<< "$request")" == ubuntu-24.04 ]]
[[ "$(jq -r '.ssh_keys[0]' <<< "$request")" == 9876 ]]
[[ -f "$HOME/.local/state/metator-acceptance/hetzner/43210" ]]
[[ "$(<"$HOME/.local/state/metator-acceptance/hetzner/43210")" == *'9876'* ]]

"$ROOT_DIR/tests/acceptance/providers/hetzner/destroy.sh" 43210
[[ ! -e "$HOME/.local/state/metator-acceptance/hetzner/43210" ]]
[[ ! -e "$HOME/.ssh/id_ed25519" && ! -e "$HOME/.ssh/id_ed25519.pub" ]]
[[ "$(<"$TEST_CURL_CALLS")" == *'POST https://api.hetzner.cloud/v1/servers'* ]]
[[ "$(<"$TEST_CURL_CALLS")" == *'POST https://api.hetzner.cloud/v1/ssh_keys'* ]]
[[ "$(<"$TEST_CURL_CALLS")" == *'DELETE https://api.hetzner.cloud/v1/servers/43210'* ]]
[[ "$(<"$TEST_CURL_CALLS")" == *'DELETE https://api.hetzner.cloud/v1/ssh_keys/9876'* ]]
[[ "$(<"$TEST_CURL_CALLS")" == *'GET https://api.hetzner.cloud/v1/ssh_keys/9876'* ]]

printf '%s\n' 'Acceptance provider lifecycle checks passed.'
