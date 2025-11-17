FROM python:3.14.0-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl

RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public | tee /etc/apt/keyrings/salt-archive-keyring.pgp \
    && curl -fsSL https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.sources | tee /etc/apt/sources.list.d/salt.sources

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3-dev openssh-client salt-master salt-minion \
    && rm -rf /var/lib/apt/lists/*

RUN pip install contextvars
