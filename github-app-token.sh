#!/usr/bin/env bash
# Generates a fresh GitHub App installation token on each call.
# Used as a git credential helper and gh auth token source.
set -euo pipefail

PEM_FILE="${GITHUB_APP_PEM:-/home/dev/.github-app-key.pem}"
APP_ID="${GITHUB_APP_CLIENT_ID:-}"
INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-}"

if [[ -z "$APP_ID" || -z "$INSTALLATION_ID" || ! -f "$PEM_FILE" ]]; then
    exit 1
fi

# Generate JWT
now=$(date +%s)
iat=$((now - 60))
exp=$((now + 600))

header=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
payload=$(printf '{"iss":"%s","iat":%d,"exp":%d}' "$APP_ID" "$iat" "$exp" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$PEM_FILE" -binary | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

jwt="${header}.${payload}.${signature}"

# Exchange JWT for installation access token
token_response=$(curl -sf -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens")

token=$(echo "$token_response" | jq -r '.token // empty')

if [[ -z "$token" ]]; then
    exit 1
fi

# If called as a git credential helper (stdin has protocol/host), output credentials
if [[ "${1:-}" == "get" ]]; then
    # Read stdin to check it's for github.com
    while IFS='=' read -r key value; do
        [[ "$key" == "host" ]] && host="$value"
    done
    if [[ "${host:-}" == "github.com" ]]; then
        echo "protocol=https"
        echo "host=github.com"
        echo "username=x-access-token"
        echo "password=${token}"
    fi
else
    # Called directly — just print the token (for gh auth)
    echo "$token"
fi
