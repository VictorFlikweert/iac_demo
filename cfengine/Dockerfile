FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    CFENGINE_REPO_URL=https://cfengine.com/pub/apt/packages \
    CFENGINE_GPG_URL=https://cfengine.com/pub/gpg.key

# Install CFEngine Community packages and basic tooling.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    python3 \
    python3-venv \
    vim-tiny \
 && curl -fsSL "${CFENGINE_GPG_URL}" | gpg --dearmor -o /etc/apt/trusted.gpg.d/cfengine.gpg \
 && echo "deb ${CFENGINE_REPO_URL} stable main" > /etc/apt/sources.list.d/cfengine-community.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends cfengine-community \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /workspace

# Keep the container running so scripts can exec cf-agent on demand.
CMD ["sleep", "infinity"]
