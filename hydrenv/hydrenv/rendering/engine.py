"""Template rendering engine."""

from __future__ import annotations

import logging
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined, Template

from ..core.models import RenderConfig, RenderTask
from .io import atomic_write_text

logger = logging.getLogger(__name__)


def load_template(template_path: Path) -> Template:
    """Load a Jinja2 template from a file path.

    Args:
        template_path: Path to the template file

    Returns:
        Compiled Jinja2 template
    """
    if not template_path.exists():
        raise FileNotFoundError(f"Template not found: {template_path}")

    # Use template's parent directory as loader search path
    loader = FileSystemLoader(str(template_path.parent))
    env = Environment(
        loader=loader,
        undefined=StrictUndefined,
        autoescape=False,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )

    return env.get_template(template_path.name)


def render_task(
    task: RenderTask, context: dict, dest_root: Path, file_mode: int
) -> Path:
    """Render a single template task.

    Args:
        task: Render task to execute
        context: Template context data
        dest_root: Base directory for relative paths
        file_mode: File permissions

    Returns:
        Output file path
    """
    logger.debug(f"Rendering template: {task.template_path}")

    template = load_template(task.template_path)
    rendered_text = template.render(**context)

    output_path = task.output_path
    if not output_path.is_absolute():
        output_path = dest_root / output_path

    atomic_write_text(output_path, rendered_text, mode=file_mode)
    logger.info(f"Rendered {task.template_path} → {output_path}")

    return output_path


def render_all(config: RenderConfig, context: dict) -> list[Path]:
    """Render all configured templates.

    Args:
        config: Render configuration
        context: Template context data

    Returns:
        List of output file paths
    """
    logger.info(f"Rendering {len(config.tasks)} template(s)")

    outputs = [
        render_task(task, context, config.dest_root, config.file_mode)
        for task in config.tasks
    ]

    logger.info(f"Successfully rendered {len(outputs)} file(s)")
    return outputs
