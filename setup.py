import os
import sys

from setuptools import Extension, setup

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backend_build import iter_modules

# The Python package lives under Multi-AI/ (see package_dir below). The .pyx
# files there are the source of truth, but this build does NOT run Cython on
# them — it compiles the committed .c files (checked in beside each .pyx)
# straight to native extension modules. The runtime imports the compiled
# .pyd/.so, never the .pyx or .c (see multi_ai/server.pyx's _load_model_module).
#
# scripts/regen_cython.py is the one place Cython runs: it regenerates every
# .c from its .pyx at a pinned Cython version. Change a .pyx, run that script,
# commit the .c it produces. .github/workflows/backend-check.yml fails the
# build if a committed .c doesn't match what its .pyx currently generates,
# which is what stops a stale .c shipping — the failure that broke the v1.0.1
# release (a server.pyx fix whose .c hadn't been regenerated listed zero
# models). That guarantee used to come from cythonize(force=True) here; moving
# it to a CI check keeps Cython (and pinning its exact codegen) out of the
# packaging path entirely.

extensions = []
stale = []
for module, pyx, c_path in iter_modules():
    if not os.path.exists(c_path):
        stale.append((pyx, c_path))
        continue
    extensions.append(Extension(module, [c_path]))

if stale:
    raise SystemExit(
        "No generated C found for:\n"
        + "\n".join(f"  {pyx}  ->  {c}" for pyx, c in stale)
        + "\n\nRun:  python scripts/regen_cython.py"
    )

setup(
    name="Multi-AI",
    version="0.1",
    packages=["multi_ai", "multi_ai.models"],
    package_dir={"": "Multi-AI"},
    ext_modules=extensions,
    # A compiled extension module can't be run as a __main__ script the way
    # `python server.pyx` used to be, so the server gets a real entry point.
    entry_points={"console_scripts": ["multi-ai-server = multi_ai.server:run"]},
)
