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

    # If config doesn't exist, the server has never been run — start it on the
    # default port so it can write the config file, then fall through to re-read it.
    if [[ ! -f "$argent_config" ]]; then
        local default_port=4000
        echo "argent tool-server config not found — starting on port ${default_port}..."
        argent server start --host 0.0.0.0 --port "${default_port}" --detach
        # Wait for the server to write the config file (3 attempts, 2s apart)
        local i
        for i in 1 2 3; do
            sleep 2
            [[ -f "$argent_config" ]] && break
        done
        if [[ ! -f "$argent_config" ]]; then
            echo "Warning: argent tool-server failed to start — skipping auto-link"
            return
        fi
    fi

    # Read token and port from config
    local argent_token argent_port
    argent_token="$(jq -r '.token // empty' "$argent_config" 2>/dev/null)"
    argent_port="$(jq -r '.port // empty' "$argent_config" 2>/dev/null)"

    # Validate both fields are present
    if [[ -z "$argent_token" || -z "$argent_port" ]]; then
        echo "Warning: argent tool-server.json missing token or port — skipping auto-link"
        return
    fi

    # If the server is not reachable, attempt to start it
    if ! curl -sf --max-time 2 "http://127.0.0.1:${argent_port}/health" >/dev/null 2>&1; then
        echo "argent tool-server not running — starting on port ${argent_port}..."
        argent server start --host 0.0.0.0 --port "${argent_port}" --detach
        # Retry health check (3 attempts, 2s apart)
        local i started=0
        for i in 1 2 3; do
            sleep 2
            if curl -sf --max-time 2 "http://127.0.0.1:${argent_port}/health" >/dev/null 2>&1; then
                started=1
                break
            fi
        done
        if [[ "$started" -eq 0 ]]; then
            echo "Warning: argent tool-server failed to start — skipping auto-link"
            return
        fi
        echo "argent tool-server started on port ${argent_port} — auto-link enabled"
    else
        echo "argent tool-server detected on port ${argent_port} — auto-link enabled"
    fi

    docker_args+=(-e "ARGENT_TOOL_SERVER_TOKEN=$argent_token")
    docker_args+=(-e "ARGENT_TOOL_SERVER_PORT=$argent_port")
}

start_container() {
    local docker_args=(
        --name "$CONTAINER_NAME"
        --hostname claude-sandbox
        -it
        -v "$PROJECTS_DIR:/home/dev/projects"
        -v "$CLAUDE_DIR:/home/dev/.claude"
        -v "claude-sandbox-ide:/home/dev/.claude/ide"
        -v "claude-sandbox-nvim-data:/home/dev/.local/share/nvim"

        -v "$(cd "$(dirname "$0")" && pwd)/.claude.json:/home/dev/.claude.json"
        -v "$(cd "$(dirname "$0")" && pwd)/zsh/.zsh_history:/home/dev/.zsh_history"
        -w /home/dev/projects
    )

    # Mount GitHub App private key if it exists
    if [[ -f "$GITHUB_APP_PEM" ]]; then
        docker_args+=(-v "$GITHUB_APP_PEM:/home/dev/.github-app-key.pem:ro")
        docker_args+=(-e "GITHUB_APP_CLIENT_ID=$GITHUB_APP_CLIENT_ID")
        docker_args+=(-e "GITHUB_APP_INSTALLATION_ID=$GITHUB_APP_INSTALLATION_ID")
    else
        echo "Warning: GITHUB_APP_PEM not set or file not found — git/gh auth will not be configured"
    fi

    # Pass ANTHROPIC_API_KEY if set
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        docker_args+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
    fi

    # Pass argent tool-server token and port if the server is configured and reachable
    inject_argent_env

    # If isolated mode, add iptables capability and run with network restrictions
    if [[ "$ISOLATED" == true ]]; then
        docker_args+=(--cap-add NET_ADMIN)
    fi

    echo "Starting claude-sandbox container..."
    if [[ "$ISOLATED" == true ]]; then
        # Start detached, apply firewall rules, then attach
        docker run -d "${docker_args[@]}" "$IMAGE_NAME" sleep infinity
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
        docker exec -it "$CONTAINER_NAME" /bin/zsh
    else
        docker run "${docker_args[@]}" "$IMAGE_NAME"
    fi
}

attach_container() {
    echo "Attaching to running claude-sandbox container..."
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
