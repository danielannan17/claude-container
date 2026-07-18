#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env if present
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

CONTAINER_NAME="claude-sandbox"
IMAGE_NAME="claude-sandbox"
PROJECTS_DIR="${CLAUDE_SANDBOX_PROJECTS:-$HOME/Projects}"
PROJECTS_DIR="${PROJECTS_DIR/#\~/$HOME}"
CLAUDE_DIR="${CLAUDE_SANDBOX_CLAUDE_DIR:-$HOME/.claude}"
CLAUDE_DIR="${CLAUDE_DIR/#\~/$HOME}"
GITHUB_APP_PEM="${GITHUB_APP_PEM/#\~/$HOME}"
GITHUB_APP_CLIENT_ID="${GITHUB_APP_CLIENT_ID:-}"
GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-}"
ISOLATED=false

usage() {
    echo "Usage: claude-sandbox [--isolated] [start|stop|status|build]"
    echo ""
    echo "Commands:"
    echo "  (no args)    Start or attach to the sandbox container"
    echo "  stop         Stop the sandbox container"
    echo "  status       Show container status"
    echo "  build        Rebuild the Docker image"
    echo ""
    echo "Options:"
    echo "  --isolated   Block all internet except Anthropic API"
}

build_image() {
    local build_dir
    build_dir="$(cd "$(dirname "$0")" && pwd)"

    # Copy zsh config into build context
    cp "$HOME/.zshrc" "$build_dir/zsh/.zshrc"
    cp "$HOME/.gitconfig" "$build_dir/zsh/.gitconfig"
    rm -rf "$build_dir/zsh/.oh-my-zsh"
    rsync -a --exclude '.git' "$HOME/.oh-my-zsh/" "$build_dir/zsh/.oh-my-zsh/"

    # Copy nvim config into build context
    rm -rf "$build_dir/nvim"
    rsync -a --exclude '.git' "$HOME/.config/nvim/" "$build_dir/nvim/"

    echo "Building claude-sandbox image..."
    docker build \
        --build-arg HOST_UID="$(id -u)" \
        --build-arg HOST_GID="$(id -g)" \
        -t "$IMAGE_NAME" \
        "$build_dir"

    # Clean up
    rm "$build_dir/zsh/.zshrc"
    rm "$build_dir/zsh/.gitconfig"
    rm -rf "$build_dir/zsh/.oh-my-zsh"
    rm -rf "$build_dir/nvim"
}

inject_argent_env() {
    # Check argent is installed
    if ! command -v argent >/dev/null 2>&1; then
        echo "argent not installed, skipping tool-server link"
        return
    fi

    local argent_config="$HOME/.argent/tool-server.json"

    _argent_server_status() { argent server status --json 2>/dev/null; }
    _argent_server_healthy() {
        [[ "$(_argent_server_status | jq -r '.healthy // false')" == "true" ]]
    }
    _argent_server_reachable_from_container() {
        local host
        host="$(_argent_server_status | jq -r '.host // empty')"
        [[ "$host" == "0.0.0.0" || "$host" == "::" ]]
    }

    _argent_start() {
        argent server start --host 0.0.0.0 --detach &>/dev/null &
        local i
        for i in 1 2 3 4 5; do
            sleep 2
            _argent_server_healthy && return 0
        done
        return 1
    }

    if ! _argent_server_healthy; then
        echo "argent tool-server not running — starting..."
        if ! _argent_start; then
            echo "Warning: argent tool-server failed to start — skipping auto-link"
            unset -f _argent_server_status _argent_server_healthy _argent_server_reachable_from_container _argent_start
            return
        fi
        echo "argent tool-server started — auto-link enabled"
    elif ! _argent_server_reachable_from_container; then
        local argent_port
        argent_port="$(_argent_server_status | jq -r '.port // empty')"
        echo "argent tool-server running on localhost only (port ${argent_port}) — restarting on 0.0.0.0..."
        argent server stop
        if ! _argent_start; then
            echo "Warning: argent tool-server failed to restart — skipping auto-link"
            unset -f _argent_server_status _argent_server_healthy _argent_server_reachable_from_container _argent_start
            return
        fi
        echo "argent tool-server restarted — auto-link enabled"
    else
        local argent_port
        argent_port="$(_argent_server_status | jq -r '.port // empty')"
        echo "argent tool-server detected on port ${argent_port} — auto-link enabled"
    fi

    unset -f _argent_server_status _argent_server_healthy _argent_server_reachable_from_container _argent_start

    local argent_token argent_port
    argent_token="$(jq -r '.token // empty' "$argent_config" 2>/dev/null)"
    argent_port="$(jq -r '.port // empty' "$argent_config" 2>/dev/null)"

    if [[ -z "$argent_token" || -z "$argent_port" ]]; then
        echo "Warning: could not read argent token/port — skipping auto-link"
        return
    fi

    docker_args+=(-e "ARGENT_TOOL_SERVER_TOKEN=$argent_token")
    docker_args+=(-e "ARGENT_TOOL_SERVER_PORT=$argent_port")
}

inject_voicemode_env() {
    # Check voicemode is installed
    if ! command -v voicemode >/dev/null 2>&1; then
        echo "voicemode not installed, skipping"
        return
    fi

    _voicemode_running() {
        voicemode service status voicemode >/dev/null 2>&1
    }

    local port="${VOICEMODE_SERVE_PORT:-8765}"

    if ! _voicemode_running; then
        echo "voicemode serve not running — starting on port ${port}..."
        mkdir -p "$HOME/.voicemode"
        voicemode serve --host 0.0.0.0 --port "${port}" --allow-ip 172.17.0.0/16 \
            >"$HOME/.voicemode/serve.log" 2>&1 &
        # Wait for the service to become running (3 attempts, 2s apart)
        local i started=0
        for i in 1 2 3; do
            sleep 2
            if _voicemode_running; then
                started=1
                break
            fi
        done
        if [[ "$started" -eq 0 ]]; then
            echo "Warning: voicemode serve failed to start — skipping"
            unset -f _voicemode_running
            return
        fi
        echo "voicemode serve started on port ${port} — container will connect via HTTP"
    else
        port="$(voicemode service status voicemode 2>/dev/null | awk '/Port:/{print $NF}')"
        echo "voicemode serve detected on port ${port} — container will connect via HTTP"
    fi

    unset -f _voicemode_running

    docker_args+=(-e "VOICEMODE_SERVE_PORT=${port}")
}

inject_superwhisper_env() {
    local port="${SUPERWHISPER_RELAY_PORT:-9001}"

    if ! curl -sf "http://localhost:${port}/health" >/dev/null 2>&1; then
        echo "Warning: superwhisper relay not reachable on port ${port} — skipping"
        return
    fi

    echo "superwhisper relay detected on port ${port} — container will connect via HTTP"
    docker_args+=(-e "SUPERWHISPER_RELAY_PORT=${port}")
}

start_container() {
    local docker_args=(
        --name "$CONTAINER_NAME"
        --hostname claude-sandbox
        -it
        -p 8766:8766
        -v "$PROJECTS_DIR:/Users/daniel/Projects"
        -v "$CLAUDE_DIR:/Users/daniel/.claude"
        -v "claude-sandbox-ide:/Users/daniel/.claude/ide"
        -v "claude-sandbox-nvim-data:/Users/daniel/.local/share/nvim"

        -v "$(cd "$(dirname "$0")" && pwd)/.claude.json:/Users/daniel/.claude.json"
        -v "$(cd "$(dirname "$0")" && pwd)/zsh/.zsh_history:/Users/daniel/.zsh_history"
        -w /Users/daniel/Projects/personal-agent-marketplace/personal-agent
    )

    # Mount GitHub App private key if it exists
    if [[ -f "$GITHUB_APP_PEM" ]]; then
        docker_args+=(-v "$GITHUB_APP_PEM:/Users/daniel/.github-app-key.pem:ro")
        docker_args+=(-e "GITHUB_APP_CLIENT_ID=$GITHUB_APP_CLIENT_ID")
        docker_args+=(-e "GITHUB_APP_INSTALLATION_ID=$GITHUB_APP_INSTALLATION_ID")
    else
        echo "Warning: GITHUB_APP_PEM not set or file not found — git/gh auth will not be configured"
    fi

    # Pass ANTHROPIC_API_KEY if set
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        docker_args+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
    fi

    docker_args+=(-e "BRAIN_REPO_PATH=/Users/daniel/Projects/personal-agent-marketplace/personal-agent-brain")

    # Pass argent tool-server token and port if the server is configured and reachable
    inject_argent_env

    # Pass voicemode serve port if the server is reachable
    inject_voicemode_env

    # Pass superwhisper relay port if the relay is reachable
    inject_superwhisper_env

    # If isolated mode, add iptables capability and run with network restrictions
    if [[ "$ISOLATED" == true ]]; then
        docker_args+=(--cap-add NET_ADMIN)
    fi

    echo "Starting claude-sandbox container..."
    # PID 1 is `sleep infinity` so shells are exec sessions — exiting one
    # leaves the container (and every other shell) running.
    docker run -d "${docker_args[@]}" "$IMAGE_NAME" sleep infinity

    if [[ "$ISOLATED" == true ]]; then
        echo "Applying network isolation (allowing only Anthropic API)..."
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -o lo -j ACCEPT
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -p tcp --dport 443 -d api.anthropic.com -j ACCEPT
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -p tcp --dport 443 -d anthropic.com -j ACCEPT
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -p tcp --dport 443 -d api.github.com -j ACCEPT
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -p tcp --dport 443 -d github.com -j ACCEPT
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        docker exec "$CONTAINER_NAME" iptables -A OUTPUT -j DROP
        echo "Network isolated. Only Anthropic API traffic allowed."
    fi

    attach_container
}

attach_container() {
    echo "Opening shell in claude-sandbox container..."
    docker exec -it "$CONTAINER_NAME" /bin/zsh
}

stop_container() {
    echo "Stopping claude-sandbox container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null && docker rm "$CONTAINER_NAME" 2>/dev/null
    echo "Container stopped and removed."
}

container_status() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "claude-sandbox is running"
        docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Status}}\t{{.Ports}}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "claude-sandbox exists but is stopped"
    else
        echo "claude-sandbox is not running"
    fi
}

# Parse flags
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --isolated) ISOLATED=true; shift ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

case "${1:-}" in
    stop)
        stop_container
        ;;
    status)
        container_status
        ;;
    build)
        stop_container
        build_image
        ;;
    help|--help|-h)
        usage
        ;;
    "")
        # Check if image exists
        if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
            build_image
        fi

        # Check if container is already running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            attach_container
        else
            # Remove stopped container if it exists
            docker rm "$CONTAINER_NAME" 2>/dev/null || true
            start_container
        fi
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
