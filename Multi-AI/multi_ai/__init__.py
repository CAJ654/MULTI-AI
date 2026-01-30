"""Top-level package for the project.

This exposes a small API surface and imports the models subpackage.
"""

from __future__ import annotations

__all__ = ["models", "__version__"]
__version__ = "0.1.0"

from . import models  # re-export the models subpackage
