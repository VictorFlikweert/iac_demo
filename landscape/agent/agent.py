import argparse
import json
import logging
import os
import signal
import stat
import subprocess
import sys
import time
from typing import Any, Dict, Iterable, List, Optional
from urllib import error, request


def configure_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(message)s",
    )


def http_get_json(url: str, timeout: int = 10) -> Dict[str, Any]:
    req = request.Request(url=url, method="GET", headers={"Accept": "application/json"})
    with request.urlopen(req, timeout=timeout) as response:
        payload = response.read()
    return json.loads(payload.decode("utf-8"))


def http_post_json(url: str, payload: Dict[str, Any], timeout: int = 10) -> None:
    data = json.dumps(payload).encode("utf-8")
    req = request.Request(
        url=url,
        method="POST",
        data=data,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Content-Length": str(len(data)),
        },
    )
    with request.urlopen(req, timeout=timeout):
        pass


def dpkg_status(package: str) -> bool:
    probe = subprocess.run(
        ["dpkg-query", "-W", "-f", "${Status}", package],
        check=False,
        capture_output=True,
        text=True,
    )
    return probe.returncode == 0 and "installed" in probe.stdout


def _run_apt(command: List[str], env: Dict[str, str], retries: int = 5) -> None:
    delay = 2
    last_exc: Optional[subprocess.CalledProcessError] = None
    for attempt in range(1, retries + 1):
        try:
            subprocess.run(
                command,
                check=True,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            return
        except subprocess.CalledProcessError as exc:
            last_exc = exc
            combined = f"{exc.stdout}\n{exc.stderr}"
            if "Could not get lock" in combined or "Unable to acquire the dpkg frontend lock" in combined:
                logging.warning(
                    "apt lock detected while running %s (attempt %s/%s); retrying in %ss",
                    " ".join(command),
                    attempt,
                    retries,
                    delay,
                )
                time.sleep(delay)
                delay = min(delay * 2, 15)
                continue
            raise
    if last_exc:
        raise last_exc


def ensure_packages(packages: Iterable[str], allow_update: bool) -> bool:
    missing = [pkg for pkg in packages if pkg and not dpkg_status(pkg)]
    if not missing:
        return False
    logging.info("Installing packages: %s", ", ".join(missing))
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    if allow_update:
        logging.debug("Running apt-get update prior to installation")
        _run_apt(["apt-get", "update"], env)
    _run_apt(["apt-get", "install", "-y", "--no-install-recommends", *missing], env)
    return True


def ensure_file(path: str, content: str, mode: Optional[str] = None) -> bool:
    changed = False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    current = None
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as handle:
            current = handle.read()
    if current != content:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)
        logging.info("Updated managed file %s", path)
        changed = True
    if mode:
        desired_mode = int(mode, 8)
        current_mode = stat.S_IMODE(os.lstat(path).st_mode)
        if current_mode != desired_mode:
            os.chmod(path, desired_mode)
            logging.debug("Adjusted mode for %s to %s", path, mode)
            changed = True
    return changed


def ensure_files(files: Iterable[Dict[str, Any]]) -> bool:
    changed = False
    for file_item in files:
        path = file_item["path"]
        content = file_item.get("content", "")
        mode = file_item.get("mode")
        if ensure_file(path, content, mode):
            changed = True
    return changed


def collect_exports(exports: Iterable[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    collected: Dict[str, Dict[str, Any]] = {}
    for export in exports:
        key = export["key"]
        path = export["path"]
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding=export.get("encoding", "utf-8")) as handle:
            content = handle.read()
        collected[key] = {
            "path": path,
            "content": content,
            "mtime": os.path.getmtime(path),
        }
    return collected


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Landscape demo agent")
    parser.add_argument("--once", action="store_true", help="Run a single reconcile cycle and exit")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    controller = os.environ.get("LANDSCAPE_CONTROLLER", "http://landscape-controller:8028")
    node_name = os.environ.get("LANDSCAPE_NODE_NAME", "unnamed-node")
    interval = int(os.environ.get("LANDSCAPE_LOOP_INTERVAL", "30"))
    log_level = os.environ.get("LANDSCAPE_LOG_LEVEL", "INFO")

    configure_logging(log_level)
    logging.info("Starting Landscape agent for node %s (controller: %s)", node_name, controller)

    stop_requested = False

    def handle_signal(signum: int, _frame: Any) -> None:
        nonlocal stop_requested
        logging.info("Signal %s received, stopping agent loop", signum)
        stop_requested = True

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    while True:
        try:
            desired_state = http_get_json(f"{controller}/state/{node_name}")
        except error.URLError as exc:
            logging.error("Unable to fetch desired state: %s", exc)
            time.sleep(min(interval, 10))
            if args.once:
                sys.exit(2)
            if stop_requested:
                break
            continue
        packages = desired_state.get("packages", [])
        files = desired_state.get("files", [])
        exports = desired_state.get("exports", [])
        apt_update = bool(desired_state.get("apt_update", False))

        changes = False
        try:
            if ensure_packages(packages, allow_update=apt_update):
                changes = True
            if ensure_files(files):
                changes = True
        except subprocess.CalledProcessError as exc:
            logging.error("Error applying desired state: %s", exc)

        export_payload = collect_exports(exports)
        report_payload = {
            "node": node_name,
            "revision": desired_state.get("revision"),
            "changes_applied": changes,
            "exports": export_payload,
        }
        try:
            http_post_json(f"{controller}/reports", report_payload)
        except error.URLError as exc:
            logging.warning("Failed to publish report: %s", exc)

        if args.once:
            break
        if stop_requested:
            break
        time.sleep(interval)


if __name__ == "__main__":
    main()
