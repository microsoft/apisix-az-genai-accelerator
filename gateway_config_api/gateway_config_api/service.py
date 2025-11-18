from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Any

import yaml


class ConfigUpdateError(Exception):
    """Raised when the APISIX configuration cannot be updated."""


def _strip_end_marker(lines: list[str]) -> tuple[list[str], bool]:
    if lines and lines[-1].strip() == "#END":
        return lines[:-1], True
    return lines, False


def _matches_identifier(instance: dict[str, Any], target: str) -> bool:
    target_lower = target.lower()
    for key in ("id", "name"):
        value = instance.get(key)
        if isinstance(value, str) and value.lower() == target_lower:
            return True
    override = instance.get("override")
    if isinstance(override, dict):
        endpoint = override.get("endpoint")
        if isinstance(endpoint, str) and endpoint.lower() == target_lower:
            return True
    return False


def _select_primary_index(instances: list[dict[str, Any]], preferred: list[str]) -> int:
    if not instances:
        raise ConfigUpdateError("No instances defined for latency-routing route")
    for pref in preferred:
        for idx, inst in enumerate(instances):
            if _matches_identifier(inst, pref):
                return idx
    return 0  # fallback to first


def update_latency_route_weights(conf_path: Path, preferred_backends: list[str]) -> int:
    if not conf_path.exists():
        raise ConfigUpdateError(f"APISIX config not found at {conf_path}")

    raw_lines = conf_path.read_text().splitlines()
    stripped_lines, had_end_marker = _strip_end_marker(raw_lines)
    data = yaml.safe_load("\n".join(stripped_lines)) or {}

    routes = data.get("routes")
    if not isinstance(routes, list):
        raise ConfigUpdateError("APISIX config is missing 'routes' list")

    target_route: dict[str, Any] | None = None
    for route in routes:
        if isinstance(route, dict) and route.get("name") == "latency-routing":
            target_route = route
            break

    if target_route is None:
        raise ConfigUpdateError("Route 'latency-routing' not found")

    plugins = target_route.get("plugins")
    if not isinstance(plugins, dict):
        raise ConfigUpdateError("Route plugins missing on 'latency-routing'")

    ai_proxy = plugins.get("ai-proxy-multi")
    if not isinstance(ai_proxy, dict):
        raise ConfigUpdateError("ai-proxy-multi plugin not configured on 'latency-routing'")

    instances = ai_proxy.get("instances")
    if not isinstance(instances, list):
        raise ConfigUpdateError("ai-proxy-multi.instances must be a list")

    primary_idx = _select_primary_index(instances, preferred_backends)
    changed = 0
    for idx, inst in enumerate(instances):
        if not isinstance(inst, dict):
            continue
        desired_weight = 100 if idx == primary_idx else 0
        if inst.get("weight") != desired_weight:
            inst["weight"] = desired_weight
            changed += 1

    _atomic_write(conf_path, data, had_end_marker)
    return changed


def _atomic_write(conf_path: Path, payload: dict[str, Any], append_end_marker: bool) -> None:
    conf_dir = conf_path.parent
    tmp_fd, tmp_name = tempfile.mkstemp(dir=conf_dir, prefix=f"{conf_path.name}.")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as handle:
            yaml.safe_dump(
                payload,
                handle,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=False,
            )
            if append_end_marker:
                handle.write("#END\n")
        Path(tmp_name).replace(conf_path)
        os.chmod(conf_path, 0o644)
        conf_path.touch()
    finally:
        if os.path.exists(tmp_name):
            os.remove(tmp_name)
