#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
worker_file="$ROOT_DIR/stubs/scripts/steps/09-workers.sh"

grep -Fq -- '--timeout=60' "$worker_file"
if grep -Fq -- '--timeout=90' "$worker_file"; then
    printf '%s\n' 'FAIL queue worker timeout equals the retry interval' >&2
    exit 1
fi

printf '%s\n' 'Queue timeout checks passed.'
