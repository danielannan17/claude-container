# Auto-link argent to the host tool-server on shell start.
# Runs only when the token env var is set and the container is not already linked.
if [[ -n "${ARGENT_TOOL_SERVER_TOKEN:-}" && ! -f "$HOME/.argent/link.json" ]]; then
    argent link \
        --host host.docker.internal \
        --port "${ARGENT_TOOL_SERVER_PORT:-4000}" \
        --token "$ARGENT_TOOL_SERVER_TOKEN" \
        >/dev/null 2>&1 || true
fi
