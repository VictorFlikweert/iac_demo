"""
Custom Salt event returner that forwards events to the demo backend.
"""

from __future__ import annotations

import json
import logging
import ssl
from typing import Any, Dict, Iterable, Mapping
from urllib import error, request

log = logging.getLogger(__name__)

__virtualname__ = "salt_backend"


def __virtual__() -> str:
  return __virtualname__


def _get_cfg() -> Dict[str, Any]:
  opts = globals().get("__opts__", {})
  cfg = opts.get(__virtualname__, {}).copy()
  cfg.setdefault("url", "http://backend:8080/returns")
  headers = cfg.get("header_dict")
  if not isinstance(headers, dict):
    headers = {"Content-Type": "application/json"}
  cfg["headers"] = headers
  cfg.setdefault("verify_ssl", False)
  cfg.setdefault("timeout", 5)
  return cfg


def _post(url: str, headers: Mapping[str, str], verify_ssl: bool, timeout: int, payload: Mapping[str, Any]) -> None:
  data = json.dumps(payload, default=str).encode("utf-8")
  req = request.Request(url, data=data, headers=headers, method="POST")
  context = None
  if url.lower().startswith("https") and not verify_ssl:
    context = ssl._create_unverified_context()
  with request.urlopen(req, timeout=timeout, context=context) as resp:
    resp.read()  # ensure request completes


def event_return(events: Iterable[Mapping[str, Any]]) -> bool:
  cfg = _get_cfg()
  payload = {"events": list(events)}
  try:
    _post(cfg["url"], cfg["headers"], cfg["verify_ssl"], cfg["timeout"], payload)
  except (error.URLError, error.HTTPError, ssl.SSLError, OSError) as exc:
    log.error("salt_backend returner failed to send events to %s: %s", cfg["url"], exc)
    return False
  return True
