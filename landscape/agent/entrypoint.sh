#!/usr/bin/env bash
set -euo pipefail

exec python3 /opt/landscape/agent.py "$@"
