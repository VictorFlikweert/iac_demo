"""
Beacon that watches for state.apply return events and pushes simple metrics to a Prometheus Pushgateway.

Configuration example (minion conf or managed via beacons.present):

beacons:
  - state_metrics:
      interval: 15
      pushgateway: http://pushgateway:9091
      job: salt_state
"""

import os
import time
import urllib.error
import urllib.request

import salt.utils.event

__virtualname__ = "state_metrics"


def __virtual__():
  return __virtualname__


def _get_event_listener():
  if "state_metrics_event" not in __context__:
    __context__["state_metrics_event"] = salt.utils.event.get_event(
      "minion", opts=__opts__, listen=False
    )
  return __context__["state_metrics_event"]


def _push_metrics(pushgateway, job, instance, metrics):
  body = "\n".join(metrics) + "\n"
  target = f"{pushgateway.rstrip('/')}/metrics/job/{job}/instance/{instance}"
  req = urllib.request.Request(target, data=body.encode("utf-8"), method="PUT")
  req.add_header("Content-Type", "text/plain; version=0.0.4")
  with urllib.request.urlopen(req, timeout=5) as resp:
    resp.read()


def _summarize_state_return(ret_data):
  summary = {
    "states": 0,
    "changed": 0,
    "failed": 0,
    "duration_ms": 0.0,
  }
  if not isinstance(ret_data, dict):
    return summary
  for _, result in ret_data.items():
    if not isinstance(result, dict):
      continue
    summary["states"] += 1
    if result.get("changes"):
      summary["changed"] += 1
    if result.get("result") is False:
      summary["failed"] += 1
    summary["duration_ms"] += float(result.get("duration", 0.0))
  return summary


def beacon(config):
  # Normalize beacon config, which may be provided as a dict or a list of dicts under the beacon name.
  cfg = {}
  if isinstance(config, dict):
    cfg = config
  elif isinstance(config, list) and config:
    # Merge list items that are dicts into one config.
    for item in config:
      if isinstance(item, dict):
        cfg.update(item)

  interval = cfg.get("interval", 15)
  pushgateway = cfg.get("pushgateway", "http://pushgateway:9091")
  job = cfg.get("job", "salt_state")
  now = time.time()

  evt = _get_event_listener()
  metrics = []

  while True:
    data = evt.get_event(wait=0.01)
    if not data:
      break

    tag = data.get("tag", "")
    if not (tag.startswith("salt/job/") and tag.endswith("/ret")):
      continue
    if data.get("fun") != "state.apply":
      continue

    instance = __grains__.get("id", "unknown")
    ret_data = data.get("return", {})
    summary = _summarize_state_return(ret_data)
    success = 1 if summary["failed"] == 0 else 0
    metrics.append(
      f'salt_state_last_success{{instance="{instance}"}} {success}'
    )
    metrics.append(
      f'salt_state_duration_seconds{{instance="{instance}"}} {summary["duration_ms"]/1000.0}'
    )
    metrics.append(
      f'salt_state_states_total{{instance="{instance}"}} {summary["states"]}'
    )
    metrics.append(
      f'salt_state_changes_total{{instance="{instance}"}} {summary["changed"]}'
    )
    metrics.append(
      f'salt_state_failures_total{{instance="{instance}"}} {summary["failed"]}'
    )

  if not metrics:
    return []

  try:
    _push_metrics(pushgateway, job, __grains__.get("id", "unknown"), metrics)
  except Exception as exc:  # noqa: BLE001
    return [
      {
        "tag": "state_metrics/error",
        "message": f"Failed to push metrics: {exc}",
      }
    ]

  return [{"tag": "state_metrics/pushed", "time": now}]
