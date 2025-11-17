"""Ansible callback to push run metrics to Prometheus Pushgateway."""

from __future__ import annotations

import os
import time
import urllib.request
import urllib.error
from collections import Counter, defaultdict

from ansible.plugins.callback import CallbackBase

DOCUMENTATION = r"""
    callback: prometheus_pushgateway
    type: notification
    short_description: Push Ansible run metrics to Prometheus Pushgateway
    description:
      - Publishes metrics for playbook runs to a Prometheus Pushgateway.
      - Metrics include duration, per-status counts, and per-host status counts.
    version_added: "2.9"
    requirements:
      - urllib in stdlib (no external deps)
    options:
      pushgateway_url:
        description: Base URL of the Pushgateway.
        env:
          - name: PROM_PUSHGATEWAY_URL
        default: http://pushgateway:9091
      job_name:
        description: Job label for the Pushgateway.
        env:
          - name: PROM_PUSHGATEWAY_JOB
        default: ansible_pull
      instance:
        description: Instance label (defaults to node name).
        env:
          - name: PROM_PUSHGATEWAY_INSTANCE
        default: autodetected node name
"""


CALLBACK_VERSION = 2.0
CALLBACK_TYPE = "notification"
CALLBACK_NAME = "prometheus_pushgateway"
CALLBACK_NEEDS_WHITELIST = False


class CallbackModule(CallbackBase):
    def __init__(self):
        super().__init__()
        self.start_time = time.time()
        self.status_counts = Counter()
        self.host_status = defaultdict(Counter)
        self.gateway = os.getenv("PROM_PUSHGATEWAY_URL", "http://pushgateway:9091").rstrip("/")
        self.job = os.getenv("PROM_PUSHGATEWAY_JOB", "ansible_pull")
        self.instance = os.getenv("PROM_PUSHGATEWAY_INSTANCE", os.uname().nodename)

    def v2_runner_on_ok(self, result, **kwargs):
        self._record("ok", result)

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._record("failed", result)

    def v2_runner_on_skipped(self, result):
        self._record("skipped", result)

    def v2_runner_on_unreachable(self, result):
        self._record("unreachable", result)

    def v2_playbook_on_stats(self, stats):
        duration = time.time() - self.start_time
        metrics = []

        metrics.append(f'ansible_run_duration_seconds{{job="{self.job}",instance="{self.instance}"}} {duration:.3f}')

        for status, count in self.status_counts.items():
            metrics.append(
                f'ansible_task_results_total{{job="{self.job}",instance="{self.instance}",status="{status}"}} {count}'
            )

        for host, counts in self.host_status.items():
            for status, count in counts.items():
                metrics.append(
                    f'ansible_task_results_total{{job="{self.job}",instance="{self.instance}",host="{host}",status="{status}"}} {count}'
                )

        body = "\n".join(metrics) + "\n"
        target = f"{self.gateway}/metrics/job/{self.job}/instance/{self.instance}"

        req = urllib.request.Request(target, data=body.encode("utf-8"), method="PUT")
        req.add_header("Content-Type", "text/plain; version=0.0.4")
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                resp.read()
        except urllib.error.URLError as exc:
            # Degrade gracefully; metrics loss is acceptable for a callback.
            self._display.warning(f"Failed to push metrics to {target}: {exc}")

    def _record(self, status, result):
        host = getattr(result, "host", None) or getattr(result, "_host", None)
        hostname = getattr(host, "get_name", lambda: None)() if host else None
        self.status_counts[status] += 1
        if hostname:
            self.host_status[hostname][status] += 1
