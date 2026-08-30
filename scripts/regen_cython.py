"""Regenerate the committed .c files from their .pyx sources.

The .pyx files are the source of truth for the backend, but the release build
(setup.py) compiles the committed .c directly and never runs Cython — that
keeps Cython and its exact codegen out of the packaging path. This script is
the one place Cython runs: edit a .pyx, run

    python scripts/regen_cython.py

and commit the regenerated .c alongside it.

Cython is pinned (CYTHON_VERSION below). Different Cython versions emit
byte-different C for the same .pyx, so an unpinned regen would churn every
file and make the CI sync check (.github/workflows/backend-check.yml)
unreproducible. Bumping the pin is a deliberate step: change it here, install
that version, rerun this script, commit the diff.
"""
import os
import sys
from pathlib import Path

# Keep in sync with the version installed by the CI sync check and the release
# build's smoke step. See the module docstring for why this is pinned.
CYTHON_VERSION = "3.3.0"

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from backend_build import iter_modules  # noqa: E402


def _check_cython_version() -> None:
    import Cython

    if Cython.__version__ != CYTHON_VERSION:
        sys.exit(
            f"Cython {Cython.__version__} is installed but this script pins "
            f"{CYTHON_VERSION}.\n"
            f"    pip install Cython=={CYTHON_VERSION}\n"
            f"(or bump CYTHON_VERSION in {Path(__file__).name} if the change is intended)."
        )


def main() -> None:
    try:
        _check_cython_version()
    except ImportError:
        sys.exit(f"Cython isn't installed. Run: pip install Cython=={CYTHON_VERSION}")

    from Cython.Build import cythonize

    # Run from the repo root and hand cythonize repo-root-relative,
    # forward-slash paths (iter_modules already normalises the separator).
    # Cython copies the source path verbatim into each .c's metadata header, so
    # anything else — an absolute path, or OS-native backslashes — would make
    # every committed .c differ by that one line depending on where and on
    # which OS the regen ran, and the sync check would never pass.
    os.chdir(REPO_ROOT)
    pyx_paths = [pyx for _module, pyx, _c in iter_modules("Multi-AI")]

    if not pyx_paths:
        sys.exit("No .pyx sources found — run this from a clean checkout.")

    # force=True: regenerate every .c regardless of mtimes, so the output is a
    # pure function of (pyx contents, Cython version) and the sync check is
    # deterministic.
    # Same invocation the old setup.py used, so the .c come out byte-identical
    # to what shipped before this split (the .pyx carry no `# distutils:`
    # directives, so there's no per-file compiler config to thread through).
    cythonize(
        pyx_paths,
        force=True,
        compiler_directives={"language_level": "3"},
    )
    print(f"Regenerated {len(pyx_paths)} .c files with Cython {CYTHON_VERSION}.")


if __name__ == "__main__":
    main()
