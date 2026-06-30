"""Top-level package for the project.

This exposes a small API surface and imports the models subpackage.
"""

from __future__ import annotations

__all__ = ["__version__"]
__version__ = "0.1.0"

try:
    from . import models  # re-export the models subpackage
    __all__.append("models")
except ImportError:
    # models/__init__.pyx currently references stub modules that don't all
    # exist and some pull in heavy optional deps (torch, tensorflow); don't
    # let that block importing the rest of the package (e.g. multi_ai.server).
    models = None
