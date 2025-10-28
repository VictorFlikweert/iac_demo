FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    LANDSCAPE_STATE_PATH=/workspace/state/state.json \
    LANDSCAPE_EXPORTS_DIR=/workspace/state/exports \
    LANDSCAPE_BIND_ADDR=0.0.0.0 \
    LANDSCAPE_BIND_PORT=8028

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --home-dir /workspace landscape
WORKDIR /workspace

COPY controller/app.py controller/state_loader.py controller/__init__.py /workspace/controller/

EXPOSE 8028

ENTRYPOINT ["python", "/workspace/controller/app.py"]
