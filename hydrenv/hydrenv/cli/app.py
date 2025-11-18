"""Main CLI application."""

from __future__ import annotations

import logging
from pathlib import Path

import typer
from typing_extensions import Annotated

from ..core.models import RenderConfig, RenderTask
from ..environment import processor, grouping
from ..rendering import engine
from .parsers import parse_file_mode, parse_group_config, parse_render

logger = logging.getLogger(__name__)

app = typer.Typer(
    name="hydrenv",
    help="Enterprise-grade Jinja2 renderer driven by environment variables.",
)


@app.command()
def render(
    renders: Annotated[
        list[str],
        typer.Option(
            "--render",
            help="Render TEMPLATE to OUTPUT (format: TEMPLATE=OUTPUT). Repeatable.",
            metavar="TEMPLATE=OUTPUT",
        ),
    ],
    dest_root: Annotated[
        str,
        typer.Option(
            "--dest-root",
            help="Base directory for relative output paths (default: cwd).",
            metavar="DIR",
        ),
    ] = "",
    file_mode: Annotated[
        str,
        typer.Option(
            "--mode",
            help="File permissions in octal (default: 0644).",
            metavar="OCTAL",
        ),
    ] = "0644",
    indexed_groups: Annotated[
        list[str],
        typer.Option(
            "--indexed",
            help='Indexed grouping: collects PREFIX_KEY_N variables (gaps allowed). JSON format: {"prefix":"PREFIX_","required_keys":[...],"optional_keys":[...]}. Repeatable.',
            metavar="JSON",
        ),
    ] = [],
    sequential_groups: Annotated[
        list[str],
        typer.Option(
            "--sequential",
            help='Sequential grouping: collects PREFIX_KEY_0, PREFIX_KEY_1... until required key missing (no gaps). JSON format: {"prefix":"PREFIX_","required_keys":[...],"optional_keys":[...]}. Repeatable.',
            metavar="JSON",
        ),
    ] = [],
    enable_key_vault: Annotated[
        bool,
        typer.Option(
            "--enable-key-vault",
            help="Enable Key Vault context variables for template rendering.",
        ),
    ] = False,
    verbose: Annotated[
        bool,
        typer.Option(
            "--verbose",
            "-v",
            help="Enable verbose logging.",
        ),
    ] = False,
) -> None:
    """Render Jinja2 templates with environment-driven context."""
    # Configure logging
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="[%(levelname)s] %(message)s",
    )

    logger.debug("Starting hydrenv")

    # Parse configuration
    render_tasks = [
        RenderTask(template_path=Path(tpl), output_path=out)
        for tpl, out in map(parse_render, renders)
    ]
    mode = parse_file_mode(file_mode)
    dest_path = Path(dest_root) if dest_root else Path.cwd()

    config = RenderConfig(
        tasks=render_tasks,
        dest_root=dest_path,
        file_mode=mode,
    )

    logger.debug(f"Config: {len(config.tasks)} task(s)")

    # Build context
    context = processor.build_context()

    # Enhance context with Key Vault variables if requested
    if enable_key_vault:
        from ..environment import keyvault

        context = keyvault.enhance_context_with_key_vault(context)
        logger.debug("Key Vault context enhancement enabled")
    else:
        logger.debug("Key Vault context enhancement disabled")

    # Apply indexed grouping strategies
    for group_config_json in indexed_groups:
        group_config = parse_group_config(group_config_json, "indexed")
        grouping.apply_grouping_strategy(
            context,
            "indexed",
            group_config["prefix"],
            group_config["required_keys"],
            group_config.get("optional_keys"),
        )

    # Apply sequential grouping strategies
    for group_config_json in sequential_groups:
        group_config = parse_group_config(group_config_json, "sequential")
        grouping.apply_grouping_strategy(
            context,
            "sequential",
            group_config["prefix"],
            group_config["required_keys"],
            group_config.get("optional_keys"),
        )

    # Render templates
    outputs = engine.render_all(config, context)

    logger.debug(f"Completed: {len(outputs)} file(s) rendered")


def main() -> None:
    """Entry point for the CLI."""
    app()


if __name__ == "__main__":
    main()
