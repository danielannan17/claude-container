# Auto-link argent to the host tool-server on shell start.
# Runs only when tool-server credentials are available and the container is not already linked.
echo "checking for argent link"
if [[ ! -f "$HOME/.argent/link.json" ]]; then
    if [[ -f "$HOME/.argent/tool-server.json" ]]; then
        echo "tool-server.json found, using token and port from file"
        _argent_token="$(jq -r '.token // empty' "$HOME/.argent/tool-server.json" 2>/dev/null)"
        _argent_port="$(jq -r '.port // empty' "$HOME/.argent/tool-server.json" 2>/dev/null)"
    else
        echo "no tool-server.json found, using ARGENT_TOOL_SERVER_TOKEN and ARGENT_TOOL_SERVER_PORT"
        _argent_token="$ARGENT_TOOL_SERVER_TOKEN"
        _argent_port="$ARGENT_TOOL_SERVER_PORT"
    fi
    if [[ -n "$_argent_token" && -n "$_argent_port" ]]; then
        argent link \
            --host host.docker.internal \
            --port "$_argent_port" \
            --token "$_argent_token" \
            >/dev/null 2>&1 || true
    fi
    unset _argent_token _argent_port
fi
