import json
import logging
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict
from urllib.parse import urlparse

from state_loader import LandscapeState, StateError


logging.basicConfig(
    level=os.environ.get("LANDSCAPE_LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(message)s",
)

STATE_PATH = os.environ.get("LANDSCAPE_STATE_PATH", "/workspace/state/state.json")
EXPORTS_DIR = os.environ.get("LANDSCAPE_EXPORTS_DIR", "/workspace/state/exports")
BIND_ADDR = os.environ.get("LANDSCAPE_BIND_ADDR", "0.0.0.0")
BIND_PORT = int(os.environ.get("LANDSCAPE_BIND_PORT", "8028"))

STATE = LandscapeState(STATE_PATH, EXPORTS_DIR)


class LandscapeHandler(BaseHTTPRequestHandler):
    server_version = "LandscapeDemo/1.0"

    def _read_json_body(self) -> Dict[str, Any]:
        content_length = self.headers.get("Content-Length")
        length = int(content_length) if content_length else 0
        raw = self.rfile.read(length) if length else b"{}"
        if not raw:
            return {}
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON payload: {exc}") from exc

    def _respond(self, status: HTTPStatus, payload: Dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: HTTPStatus, message: str) -> None:
        logging.warning("Request error %s: %s", status.value, message)
        self._respond(status, {"error": message})

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/healthz":
            self._respond(HTTPStatus.OK, {"status": "ok"})
            return
        if parsed.path.startswith("/state/"):
            node = parsed.path[len("/state/") :].strip()
            if not node:
                self._error(HTTPStatus.BAD_REQUEST, "Node identifier missing")
                return
            try:
                desired_state = STATE.get_state_for_node(node)
            except StateError as exc:
                self._error(HTTPStatus.NOT_FOUND, str(exc))
                return
            self._respond(HTTPStatus.OK, desired_state)
            return
        self._error(HTTPStatus.NOT_FOUND, "Unknown endpoint")

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path != "/reports":
            self._error(HTTPStatus.NOT_FOUND, "Unknown endpoint")
            return
        try:
            payload = self._read_json_body()
        except ValueError as exc:
            self._error(HTTPStatus.BAD_REQUEST, str(exc))
            return
        node = payload.get("node")
        if not node:
            self._error(HTTPStatus.BAD_REQUEST, "Report must include node identifier")
            return
        STATE.record_report(node, payload)
        self._respond(HTTPStatus.OK, {"status": "received"})

    def log_message(self, fmt: str, *args: Any) -> None:  # noqa: D401, N802
        """Silence the default log output; logging is handled centrally."""
        logging.debug("%s - %s", self.address_string(), fmt % args)


def main() -> None:
    server = ThreadingHTTPServer((BIND_ADDR, BIND_PORT), LandscapeHandler)
    logging.info("Landscape demo controller listening on %s:%s", BIND_ADDR, BIND_PORT)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info("Shutting down controller")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
