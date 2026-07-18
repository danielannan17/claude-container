#!/usr/bin/env bash
# Configures git and gh CLI to use the GitHub App for auth.
# Git: uses token script as credential helper (fresh token per request).
# gh: uses GH_TOKEN env var via a shell function wrapper (fresh token per call).
set -euo pipefail

TOKEN_SCRIPT="/Users/daniel/github-app-token.sh"

if [[ ! -f /Users/daniel/.github-app-key.pem ]]; then
    echo "No GitHub App key found, skipping auth setup."
    exit 0
fi

# Test that we can get a token
if ! "$TOKEN_SCRIPT" > /dev/null 2>&1; then
    echo "Failed to generate GitHub App token. Check GITHUB_APP_CLIENT_ID, GITHUB_APP_INSTALLATION_ID, and key file."
    exit 1
fi

# Configure git to use the token script as a credential helper (fresh token each time)
git config --global --replace-all credential.helper "$TOKEN_SCRIPT"

echo "GitHub App auth configured. Tokens refresh automatically."
