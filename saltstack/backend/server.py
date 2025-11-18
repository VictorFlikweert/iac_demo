#!/usr/bin/env python3
"""Simple HTTP backend to collect Salt events."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any, Dict


HOST = "0.0.0.0"
PORT = 8080
LOG_PATH = Path(os.environ.get("BACKEND_LOG", "/data/returns.log"))


def append_log(entry: Dict[str, Any]) -> None:
  LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
  with LOG_PATH.open("a", encoding="utf-8") as log_file:
    log_file.write(json.dumps(entry, sort_keys=True) + "\n")
  print(json.dumps(entry, sort_keys=True), flush=True)


class ReturnHandler(BaseHTTPRequestHandler):
  def log_message(self, fmt: str, *args: Any) -> None:  # pragma: no cover - silence default logs
    return

  def _respond(self, code: int, body: str = "") -> None:
    self.send_response(code)
    self.send_header("Content-Type", "text/plain; charset=utf-8")
    self.end_headers()
    if body:
      self.wfile.write(body.encode("utf-8"))

  def do_GET(self) -> None:  # noqa: N802
    if self.path == "/health":
      self._respond(200, "ok\n")
    else:
      self._respond(404, "not found\n")

  def do_POST(self) -> None:  # noqa: N802
    length = int(self.headers.get("Content-Length", 0))
    payload = self.rfile.read(length) if length else b""
    try:
      data = json.loads(payload.decode("utf-8") or "{}")
    except json.JSONDecodeError:
      data = {"raw": payload.decode("utf-8", errors="replace")}
    entry = {
      "timestamp": datetime.now(timezone.utc).isoformat(),
      "path": self.path,
      "headers": {k: self.headers[k] for k in self.headers},
      "data": data,
    }
    append_log(entry)
    self._respond(202, "stored\n")


def main() -> None:
  server = HTTPServer((HOST, PORT), ReturnHandler)
  print(f"Salt backend listening on {HOST}:{PORT}, logging to {LOG_PATH}", flush=True)
  try:
    server.serve_forever()
  except KeyboardInterrupt:  # pragma: no cover
    pass
  finally:
    server.server_close()


if __name__ == "__main__":
  sys.exit(main())
