"""Domain models for template rendering configuration and context."""

from __future__ import annotations

from pathlib import Path

from pydantic import BaseModel, Field


class RenderTask(BaseModel):
    """A single template rendering task."""

    template_path: Path = Field(..., description="Template file path")
    output_path: Path = Field(..., description="Output file path")


class RenderConfig(BaseModel):
    """Configuration for the rendering process."""

    tasks: list[RenderTask] = Field(..., min_length=1, description="Render tasks")
    dest_root: Path = Field(
        default_factory=Path.cwd, description="Base output directory"
    )
    file_mode: int = Field(default=0o644, description="File permissions (octal)")
