"""CLI argument parsers and validators."""

from __future__ import annotations

import json
from pathlib import Path

import typer


def parse_render(value: str) -> tuple[str, Path]:
    """Parse a render argument in format TEMPLATE=OUTPUT."""
    if "=" not in value:
        raise typer.BadParameter(f"Must be TEMPLATE=OUTPUT, got: {value!r}")
    tpl, out = value.split("=", 1)
    return tpl, Path(out)


def parse_file_mode(value: str) -> int:
    """Parse octal file mode string."""
    try:
        return int(value, 8)
    except ValueError as e:
        raise typer.BadParameter(f"Invalid octal mode: {value!r}") from e


def parse_group_config(value: str, strategy_name: str) -> dict:
    """Parse JSON group configuration (without name field)."""
    try:
        data = json.loads(value)
    except json.JSONDecodeError as e:
        raise typer.BadParameter(f"Invalid JSON: {e}") from e

    if "name" in data:
        raise typer.BadParameter(
            f"Do not include 'name' in JSON - use --{strategy_name} flag instead"
        )

    required_fields = ["prefix", "required_keys"]
    for field in required_fields:
        if field not in data:
            raise typer.BadParameter(f"Missing required field: {field}")

    return data
