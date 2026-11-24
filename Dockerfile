FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Development tools and Python 3.12
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl gnupg git \
    openssh-client python3 python3-pip python3-venv \
    build-essential ripgrep less tmux vim unzip groff\
    && rm -rf /var/lib/apt/lists/*

# Node.js 22
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL \
       https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install the npm-distributed coding agent
RUN npm install -g @kilocode/cli

# Install the standalone coding agent
RUN curl -fsSL https://omp.sh/install -o /tmp/install-omp.sh \
    && PI_INSTALL_DIR=/usr/local/bin sh /tmp/install-omp.sh --binary \
    && rm /tmp/install-omp.sh \
    && omp --version

# Create a non-root agent user
RUN useradd -m -s /bin/bash agent \
    && mkdir -p /sandbox/NetworkWatch/.local /sandbox/NetworkWatch/.config/kilo \
    && chown -R agent:agent /sandbox /home/agent

# Install AWS CLI v2
RUN set -eu; \
    case "$(uname -m)" in \
      x86_64) AWS_ARCH=x86_64 ;; \
      aarch64) AWS_ARCH=aarch64 ;; \
      *) echo "Unsupported architecture" >&2; exit 1 ;; \
    esac; \
    curl -fsSLo /tmp/awscliv2.zip \
      "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip"; \
    unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2; \
    /tmp/awscliv2/aws/install \
      --install-dir /usr/local/aws-cli \
      --bin-dir /usr/local/bin; \
    rm -rf /tmp/awscliv2 /tmp/awscliv2.zip

# Install PostgreSQL 18.7

# PostgreSQL binaries for disposable project integration tests
# Install binaries only; the agent initializes its own database at runtime.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql-common; \
    sed -ri 's/^[# ]*create_main_cluster[ ]*=.*/create_main_cluster = false/' \
      /etc/postgresql-common/createcluster.conf; \
    install -d -m 0755 /usr/share/postgresql-common/pgdg; \
    curl -fsSL \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc; \
    gpg --show-keys --with-colons \
      /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      | grep -Fq 'B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8'; \
    printf '%s\n' \
      'Types: deb' \
      'URIs: https://apt.postgresql.org/pub/repos/apt' \
      'Suites: noble-pgdg' \
      'Components: main' \
      'Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc' \
      > /etc/apt/sources.list.d/pgdg.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      postgresql-18=18.7-1.pgdg24.04+2 \
      postgresql-client-18=18.7-1.pgdg24.04+2; \
    rm -rf /var/lib/apt/lists/*

# Make PostgreSQL administration commands available to the agent
ENV PATH="/usr/lib/postgresql/18/bin:${PATH}"

# Create a writable temporary directory for the coding agent
RUN install -d -m 700 -o agent -g agent /tmp/kilo

USER agent

# Keep agent configuration separate from project files
ENV HOME=/home/agent \
    XDG_CONFIG_HOME=/home/agent/.config \
    XDG_CACHE_HOME=/home/agent/.cache \
    XDG_DATA_HOME=/home/agent/.local/share \
    NPM_CONFIG_CACHE=/home/agent/.npm

# Initialize the standalone agent’s persistent home directory
RUN mkdir -p /home/agent/.omp/agent \
    && chown -R agent:agent /home/agent/.omp \
    && chmod 700 /home/agent/.omp

ENV AWS_DEFAULT_REGION=us-east-2 AWS_EC2_METADATA_DISABLED=true

WORKDIR /sandbox/NetworkWatch

# Configure Git to use the OpenShell GitHub credential
RUN git config --global 'credential.https://github.com.helper' \
    '!f() { if [ "$1" = get ]; then printf "username=x-access-token\npassword=%s\n" "$GITHUB_TOKEN"; fi; }; f'
