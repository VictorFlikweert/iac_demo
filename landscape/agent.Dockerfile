FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANDSCAPE_CONTROLLER=http://landscape-controller:8028 \
    LANDSCAPE_NODE_NAME=unset-node \
    LANDSCAPE_LOOP_INTERVAL=30 \
    LANDSCAPE_LOG_LEVEL=INFO

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv python3-apt python3-urllib3 apt-transport-https ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

COPY agent/agent.py /opt/landscape/agent.py
COPY agent/entrypoint.sh /usr/local/bin/landscape-agent

RUN chmod +x /usr/local/bin/landscape-agent

ENTRYPOINT ["/usr/local/bin/landscape-agent"]
