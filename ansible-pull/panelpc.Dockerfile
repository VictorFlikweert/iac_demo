FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ansible openssh-client prometheus-node-exporter \
    && rm -rf /var/lib/apt/lists/*
