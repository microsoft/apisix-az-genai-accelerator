"""Hydrenv - Environment-driven template renderer.

A functional, Pydantic-based template renderer following Python best practices.
"""

__version__ = "0.1.0"

# Configure logging for library use
import logging

logging.getLogger(__name__).addHandler(logging.NullHandler())

# Re-export main CLI entry point
from .cli import main

__all__ = ["main"]
