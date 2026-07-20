# Entry point for the backend when it runs inside a packaged Windows build.
#
# The bundled interpreter is CPython's *embeddable* distribution, which ships a
# `python._pth` file. That file replaces the normal path setup entirely and —
# this is the part that bites — makes the interpreter **ignore PYTHONPATH**. So
# the usual trick of pointing PYTHONPATH at the dependency directory silently
# does nothing, and `import torch` fails with the paths looking correct.
#
# Rather than fight the ._pth, the paths are assembled here in ordinary Python,
# after startup, where nothing is overriding anything. MULTI_AI_PATH is a
# PATH-style list written by the app (see app/lib/backend_process.dart):
# the directory holding the compiled multi_ai package, plus the user-writable
# site-packages that first-run provisioning pip-installs torch into.
#
# Works unmodified against a normal venv too, which is what `pip install -e .`
# gives you in development — there MULTI_AI_PATH is simply unset and the
# interpreter finds multi_ai on its own.

import os
import sys


def _extend_path() -> None:
    raw = os.environ.get("MULTI_AI_PATH", "")
    # Prepended in reverse so the listed order survives into sys.path.
    for entry in reversed([p for p in raw.split(os.pathsep) if p]):
        if entry not in sys.path:
            sys.path.insert(0, entry)


def main() -> int:
    _extend_path()

    # Imported only after the path is built — multi_ai lives on one of those
    # entries in a packaged build, so a module-level import would fail here.
    from multi_ai.server import run

    port = int(os.environ.get("MULTI_AI_PORT", "8000"))
    run(port=port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
