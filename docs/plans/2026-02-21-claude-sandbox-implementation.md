# Claude Sandbox Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Docker container and run script to safely execute Claude Code with `--dangerously-skip-permissions`.

**Architecture:** Dockerfile builds an Ubuntu image with Node.js, Python, git, and Claude Code. A `claude-sandbox` bash script manages the container lifecycle — starting, attaching, and stopping.

**Tech Stack:** Docker, Bash, Ubuntu 24.04 LTS, Node.js 23.x, Python 3

---

### Task 1: Create the Dockerfile

**Files:**
- Create: `Dockerfile`

**Step 1: Write the Dockerfile**

```dockerfile
FROM ubuntu:24.04

ARG HOST_UID=501
ARG HOST_GID=20

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    gnupg \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create dev user with matching host UID/GID
RUN groupadd -g ${HOST_GID} dev 2>/dev/null || true && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/bash dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Node.js 23.x via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_23.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Switch to dev user
USER dev
WORKDIR /projects

CMD ["/bin/bash"]
```

**Step 2: Build the image to verify it works**

Run: `cd /Users/daniel/Projects/claude-container && docker build --build-arg HOST_UID=$(id -u) --build-arg HOST_GID=$(id -g) -t claude-sandbox .`
Expected: Image builds successfully, final line shows tagging.

**Step 3: Verify Claude Code is installed in the image**

Run: `docker run --rm claude-sandbox claude --version`
Expected: Prints Claude Code version (e.g., `2.x.x`)

**Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Dockerfile for Claude sandbox container"
```

---

### Task 2: Create the run script

**Files:**
- Create: `claude-sandbox`

**Step 1: Write the run script**

```bash
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="claude-sandbox"
IMAGE_NAME="claude-sandbox"
PROJECTS_DIR="${CLAUDE_SANDBOX_PROJECTS:-$HOME/Projects}"
CLAUDE_DIR="${CLAUDE_SANDBOX_CLAUDE_DIR:-$HOME/.claude}"

usage() {
    echo "Usage: claude-sandbox [start|stop|status|build]"
    echo ""
    echo "Commands:"
    echo "  (no args)  Start or attach to the sandbox container"
    echo "  stop       Stop the sandbox container"
    echo "  status     Show container status"
    echo "  build      Rebuild the Docker image"
}

build_image() {
    echo "Building claude-sandbox image..."
    docker build \
        --build-arg HOST_UID="$(id -u)" \
        --build-arg HOST_GID="$(id -g)" \
        -t "$IMAGE_NAME" \
        "$(cd "$(dirname "$0")" && pwd)"
}

start_container() {
    local docker_args=(
        --name "$CONTAINER_NAME"
        --hostname claude-sandbox
        -it
        -v "$PROJECTS_DIR:/projects"
        -v "$CLAUDE_DIR:/home/dev/.claude"
        -w /projects
    )

    # Pass ANTHROPIC_API_KEY if set
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        docker_args+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
    fi

    echo "Starting claude-sandbox container..."
    docker run "${docker_args[@]}" "$IMAGE_NAME"
}

attach_container() {
    echo "Attaching to running claude-sandbox container..."
    docker exec -it "$CONTAINER_NAME" /bin/bash
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

case "${1:-}" in
    stop)
        stop_container
        ;;
    status)
        container_status
        ;;
    build)
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
```

**Step 2: Make the script executable**

Run: `chmod +x /Users/daniel/Projects/claude-container/claude-sandbox`

**Step 3: Verify the script shows help**

Run: `/Users/daniel/Projects/claude-container/claude-sandbox --help`
Expected: Prints usage information.

**Step 4: Commit**

```bash
git add claude-sandbox
git commit -m "feat: add claude-sandbox run script with smart container management"
```

---

### Task 3: Add a .gitignore and README

**Files:**
- Create: `.gitignore`

**Step 1: Write .gitignore**

```
.env
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add gitignore"
```

---

### Task 4: End-to-end test

**Step 1: Build the image**

Run: `cd /Users/daniel/Projects/claude-container && ./claude-sandbox build`
Expected: Image builds successfully.

**Step 2: Start the container and verify mounts**

Run: `./claude-sandbox` (then inside the container):
- `ls /projects` — should show your Projects directory contents
- `ls ~/.claude` — should show your Claude Code config
- `claude --version` — should print Claude Code version
- `node --version` — should print Node.js version
- `python3 --version` — should print Python version
- `git --version` — should print git version
- `whoami` — should print `dev`
- Type `exit` to leave

**Step 3: Test re-attach**

Run: Start a second terminal and run `./claude-sandbox` — should attach to the existing container.

**Step 4: Test stop**

Run: `./claude-sandbox stop`
Expected: Container stopped and removed.

**Step 5: Test status**

Run: `./claude-sandbox status`
Expected: "claude-sandbox is not running"
