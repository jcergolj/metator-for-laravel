#!/usr/bin/env bash

step_cloudflare_dns() {
    if [[ "$USE_CLOUDFLARE" != true ]]; then
        ok 'Cloudflare DNS was not selected; DNS was not changed'
        return
    fi

    command -v curl >/dev/null 2>&1 || die 'curl is not installed'
    command -v jq >/dev/null 2>&1 || die 'jq is required for Cloudflare DNS management'

    local zones_json zone_id existing_json result_count response
    zones_json="$(curl -fsS --max-time 10 \
        "https://api.cloudflare.com/client/v4/zones?name=${CF_ZONE_NAME}&status=active&per_page=1" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H 'Content-Type: application/json')" || die 'Cloudflare zone lookup failed'

    echo "$zones_json" | jq -e '.success == true' >/dev/null ||
        die 'Cloudflare rejected the API token or zone lookup'
    zone_id="$(echo "$zones_json" | jq -r '.result[0].id // empty')"
    [[ -n "$zone_id" ]] || die "Cloudflare zone was not found: $CF_ZONE_NAME"

    existing_json="$(curl -fsS --max-time 10 \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A&name=${DOMAIN}&per_page=1" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H 'Content-Type: application/json')" || die 'Cloudflare DNS lookup failed'

    echo "$existing_json" | jq -e '.success == true' >/dev/null ||
        die 'Cloudflare rejected the DNS lookup'
    result_count="$(echo "$existing_json" | jq '.result | length')"
    if [[ "$result_count" -gt 0 ]]; then
        ok "DNS A record for ${DOMAIN} already exists; skipping"
        return
    fi

    step 'Creating Cloudflare DNS A record...'
    response="$(curl -fsS --max-time 10 -X POST \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H 'Content-Type: application/json' \
        --data "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${SERVER_IP}\",\"proxied\":true}")" || {
        warn 'Cloudflare DNS record creation failed'
        ask_yes_no 'Continue without creating the DNS record?' n || exit 1
        return
    }

    if echo "$response" | jq -e '.success == true' >/dev/null; then
        ok 'Cloudflare DNS record created'
    else
        warn 'Cloudflare did not create the DNS record'
        ask_yes_no 'Continue without creating the DNS record?' n || exit 1
    fi
}
