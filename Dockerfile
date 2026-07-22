FROM ubuntu:24.04

ARG HOST_UID=501
ARG HOST_GID=20

# Avoid interactive prompts during package installation
ARG DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV HISTORY_IGNORE="(exit)"
ENV SHELL=/usr/bin/zsh
ENV PATH="/Users/daniel/.local/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    python-is-python3 \
    ca-certificates \
    gnupg \
    sudo \
    zsh \
    iptables \
    # Used for nvim
    ripgrep \
    # Used for claude code teammates
    tmux \
    && rm -rf /var/lib/apt/lists/*

# Install Neovim (latest stable from GitHub)
RUN ARCH=$(dpkg --print-architecture | sed 's/amd64/x86_64/') \
    && curl -Lo nvim.tar.gz "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH}.tar.gz" \
    && tar xf nvim.tar.gz \
    && cp -r nvim-linux-${ARCH}/* /usr/local/ \
    && rm -rf nvim.tar.gz nvim-linux-${ARCH}

# Create dev user with matching host UID/GID
RUN groupadd -g ${HOST_GID} dev 2>/dev/null || true && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} -d /Users/daniel -s /bin/zsh dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install lazygit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name' | sed 's/^v//') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x86_64/').tar.gz" \
    && tar xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin \
    && rm lazygit lazygit.tar.gz

# Install GitHub CLI
RUN (type -p wget >/dev/null || (apt-get update && apt-get install -y wget)) \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 23.x via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_23.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

ENV CXXFLAGS="-std=c++20"
ENV CXX="g++"
    # Install argent globally
RUN npm install -g @swmansion/argent

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

USER dev

# Install Claude Code (must run as dev — installer is $HOME-relative)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Copy host oh-my-zsh and zsh config
COPY --chown=dev zsh/.oh-my-zsh/ /Users/daniel/.oh-my-zsh/
COPY --chown=dev zsh/.zshrc /Users/daniel/.zshrc
COPY --chown=dev zsh/.gitconfig /Users/daniel/.gitconfig

# Copy nvim config and apply patches
COPY --chown=dev nvim/ /Users/daniel/.config/nvim/
COPY --chown=dev terminal_cmd.patch /tmp/terminal_cmd.patch
RUN cd /Users/daniel/.config/nvim && patch -p0 < /tmp/terminal_cmd.patch && rm /tmp/terminal_cmd.patch

# Pre-create dirs so named volumes inherit dev ownership (not root)
RUN mkdir -p /Users/daniel/.local/share/nvim /Users/daniel/.claude/ide /Users/daniel/.config/lazygit /Users/daniel/.venvs && touch /Users/daniel/.config/lazygit/config.yml

# Install fzf
RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && \
    ~/.fzf/install --all

# Install poetry
RUN curl -sSL https://install.python-poetry.org | python3 -

# ~/Projects is bind-mounted byte-identical from the host (see design-log 005), so
# an in-project .venv would be the SAME directory on both sides. A venv built by the
# host's Homebrew Python has Darwin binaries under it; one built in-container would
# have Linux binaries — either way the other side's `poetry run` breaks. Keep venvs
# out of the shared tree entirely, in a container-only directory.
ENV POETRY_VIRTUALENVS_IN_PROJECT=false \
    POETRY_VIRTUALENVS_PATH=/Users/daniel/.venvs

# Install gh-dash extension
RUN gh extension install dlvhdr/gh-dash

# Container-specific shell configs
COPY --chown=dev zsh/aliases.zsh /Users/daniel/.zsh_aliases
COPY --chown=dev zsh/fzf-settings.zsh /Users/daniel/.zsh_fzf
COPY --chown=dev zsh/argent.zsh /Users/daniel/.zsh_argent

# Copy GitHub App auth scripts
COPY --chown=dev github-app-auth.sh /Users/daniel/github-app-auth.sh
COPY --chown=dev github-app-token.sh /Users/daniel/github-app-token.sh

RUN echo 'source /Users/daniel/.zsh_aliases' >> ~/.zshrc && \
    echo 'source /Users/daniel/.zsh_fzf' >> ~/.zshrc && \
    echo 'source /Users/daniel/.zsh_argent' >> ~/.zshrc && \
    echo 'if [[ -f /Users/daniel/.github-app-key.pem && ! -f /tmp/.github-auth-done ]]; then /Users/daniel/github-app-auth.sh && touch /tmp/.github-auth-done; fi' >> ~/.zshrc && \
    echo 'gh() { GH_TOKEN=$(/Users/daniel/github-app-token.sh 2>/dev/null) command gh "$@"; }' >> ~/.zshrc && \
    echo 'export PROMPT='"'"'%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} )%{$fg[yellow]%}@%m %{$fg[cyan]%}%c%{$reset_color%} $(git_prompt_info)'"'"'' >> ~/.zshrc

WORKDIR /Users/daniel/Projects

CMD ["/bin/zsh"]
