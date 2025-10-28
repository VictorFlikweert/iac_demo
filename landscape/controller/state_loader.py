import copy
import json
import os
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional


class StateError(RuntimeError):
    """Raised when the desired state is invalid."""


def _ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def _export_path(exports_dir: str, node: str, key: str) -> str:
    safe_key = key.replace("/", "_")
    return os.path.join(exports_dir, f"{node}__{safe_key}.json")


def _load_json(path: str) -> Dict[str, Any]:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _write_json(path: str, payload: Dict[str, Any]) -> None:
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
    os.replace(tmp_path, path)


@dataclass
class TemplateContent:
    content: str
    revision_seed: float


class LandscapeState:
    def __init__(self, state_path: str, exports_dir: str) -> None:
        self._state_path = state_path
        self._exports_dir = exports_dir
        _ensure_dir(exports_dir)

    def _read_state(self) -> Dict[str, Any]:
        if not os.path.isfile(self._state_path):
            raise StateError(f"State file missing: {self._state_path}")
        return _load_json(self._state_path)

    def _template_revision_seed(self, template: Dict[str, Any]) -> float:
        seeds: List[float] = []
        fallback = template.get("fallback_file")
        if fallback and os.path.isfile(fallback):
            seeds.append(os.path.getmtime(fallback))
        export = template.get("export")
        if export:
            export_file = _export_path(self._exports_dir, export["node"], export["key"])
            if os.path.isfile(export_file):
                seeds.append(os.path.getmtime(export_file))
        default_content = template.get("default_content")
        if default_content:
            seeds.append(float(hash(default_content) & 0xFFFFFFFF))
        return max(seeds) if seeds else time.time()

    def _load_template(self, template_name: str, template: Dict[str, Any]) -> TemplateContent:
        export = template.get("export")
        if export:
            export_file = _export_path(self._exports_dir, export["node"], export["key"])
            if os.path.isfile(export_file):
                payload = _load_json(export_file)
                content = payload.get("content", "")
                timestamp = payload.get("timestamp")
                revision_seed = float(timestamp) if timestamp is not None else os.path.getmtime(export_file)
                return TemplateContent(content=content, revision_seed=revision_seed)
        fallback = template.get("fallback_file")
        if fallback and os.path.isfile(fallback):
            with open(fallback, encoding="utf-8") as handle:
                return TemplateContent(content=handle.read(), revision_seed=os.path.getmtime(fallback))
        default_content = template.get("default_content", "")
        return TemplateContent(content=default_content, revision_seed=time.time())

    def _resolve_group(
        self,
        group_name: str,
        groups: Dict[str, Any],
        visited: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        if visited is None:
            visited = []
        if group_name in visited:
            raise StateError(f"Cyclic group inheritance detected: {' -> '.join(visited + [group_name])}")
        if group_name not in groups:
            raise StateError(f"Unknown group '{group_name}' for topology assignment")

        definition = groups[group_name]
        base = {
            "packages": [],
            "files": [],
            "exports": [],
            "apt_update": False,
        }
        if "extends" in definition:
            parent = self._resolve_group(definition["extends"], groups, visited + [group_name])
            base = copy.deepcopy(parent)

        packages = list(base.get("packages", []))
        for pkg in definition.get("packages", []):
            if pkg not in packages:
                packages.append(pkg)
        files_by_path = {item["path"]: copy.deepcopy(item) for item in base.get("files", [])}
        for file_item in definition.get("files", []):
            files_by_path[file_item["path"]] = copy.deepcopy(file_item)
        exports_by_key = {item["key"]: copy.deepcopy(item) for item in base.get("exports", [])}
        for export_item in definition.get("exports", []):
            exports_by_key[export_item["key"]] = copy.deepcopy(export_item)

        apt_update = base.get("apt_update", False) or bool(definition.get("apt_update"))

        return {
            "packages": packages,
            "files": list(files_by_path.values()),
            "exports": list(exports_by_key.values()),
            "apt_update": apt_update,
        }

    def _materialize_files(
        self,
        files: List[Dict[str, Any]],
        templates: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        materialized: List[Dict[str, Any]] = []
        for file_item in files:
            item = copy.deepcopy(file_item)
            revision_seed = time.time()
            if "template" in item:
                template_name = item["template"]
                if template_name not in templates:
                    raise StateError(f"Unknown template '{template_name}' referenced by file {item['path']}")
                template_content = self._load_template(template_name, templates[template_name])
                item["content"] = template_content.content
                revision_seed = template_content.revision_seed
            elif "content_file" in item:
                content_file = item["content_file"]
                if not os.path.isfile(content_file):
                    raise StateError(f"content_file '{content_file}' not found for file {item['path']}")
                with open(content_file, encoding="utf-8") as handle:
                    item["content"] = handle.read()
                revision_seed = os.path.getmtime(content_file)
            item.pop("template", None)
            item.pop("content_file", None)
            item["revision_seed"] = revision_seed
            materialized.append(item)
        return materialized

    def _collect_revision_seed(
        self,
        state_data: Dict[str, Any],
        rendered_files: List[Dict[str, Any]],
    ) -> str:
        seeds: List[float] = [os.path.getmtime(self._state_path)]
        templates = state_data.get("templates", {})
        for template_name, template in templates.items():
            seeds.append(self._template_revision_seed(template))
        for file_item in rendered_files:
            seeds.append(file_item.get("revision_seed", time.time()))
        return f"{max(seeds):.0f}"

    def get_state_for_node(self, node: str) -> Dict[str, Any]:
        state_data = self._read_state()
        topology: Dict[str, str] = state_data.get("topology", {})
        groups: Dict[str, Any] = state_data.get("groups", {})
        templates: Dict[str, Any] = state_data.get("templates", {})

        if node not in topology:
            raise StateError(f"No topology assignment found for node '{node}'")
        group_name = topology[node]
        resolved = self._resolve_group(group_name, groups)
        rendered_files = self._materialize_files(resolved.get("files", []), templates)
        revision = self._collect_revision_seed(state_data, rendered_files)

        for item in rendered_files:
            item.pop("revision_seed", None)

        return {
            "node": node,
            "group": group_name,
            "revision": revision,
            "packages": resolved.get("packages", []),
            "files": rendered_files,
            "exports": resolved.get("exports", []),
            "apt_update": resolved.get("apt_update", False),
        }

    def record_report(self, node: str, payload: Dict[str, Any]) -> None:
        exports: Dict[str, Any] = payload.get("exports", {})
        timestamp = time.time()
        for key, export_payload in exports.items():
            content = export_payload.get("content")
            if content is None:
                continue
            destination = _export_path(self._exports_dir, node, key)
            _write_json(destination, {"content": content, "timestamp": timestamp})
