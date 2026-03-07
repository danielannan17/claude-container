FROM ubuntu:24.04

ARG HOST_UID=501
ARG HOST_GID=20

# Avoid interactive prompts during package installation
ARG DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV HISTORY_IGNORE="(exit)"

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
    neovim \
    zsh \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Create dev user with matching host UID/GID
RUN groupadd -g ${HOST_GID} dev 2>/dev/null || true && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/zsh dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Node.js 23.x via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_23.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Symlink macOS host paths so mounted plugin paths resolve correctly
RUN mkdir -p /Users/daniel && \
    ln -s /home/dev/.claude /Users/daniel/.claude && \
    ln -s /home/dev/projects /Users/daniel/Projects

# Copy host oh-my-zsh and zsh config
USER dev
COPY --chown=dev zsh/.oh-my-zsh/ /home/dev/.oh-my-zsh/
COPY --chown=dev zsh/.zshrc /home/dev/.zshrc

# Install fzf
RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && \
    ~/.fzf/install --all

# Container-specific shell configs
COPY --chown=dev zsh/aliases.zsh /home/dev/.zsh_aliases
COPY --chown=dev zsh/fzf-settings.zsh /home/dev/.zsh_fzf

RUN echo 'source /home/dev/.zsh_aliases' >> ~/.zshrc && \
    echo 'source /home/dev/.zsh_fzf' >> ~/.zshrc && \
    echo 'export PROMPT='"'"'%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} )%{$fg[yellow]%}@%m %{$fg[cyan]%}%c%{$reset_color%} $(git_prompt_info)'"'"'' >> ~/.zshrc
WORKDIR /projects

CMD ["/bin/zsh"]
