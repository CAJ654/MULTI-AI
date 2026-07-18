import os

from setuptools import Extension, setup
from Cython.Build import cythonize

# The Python package lives under Multi-AI/ (see package_dir below). Every .pyx
# there is compiled to a native extension module — the runtime imports the
# compiled .pyd/.so, never the .pyx source (see multi_ai/server.pyx's
# _load_model_module). The .pyx files are the source of truth; the generated
# .c and compiled .pyd/.so are build artifacts.
SRC_ROOT = "Multi-AI"

extensions = []
for root, dirs, files in os.walk(SRC_ROOT):
    rel_dir = os.path.relpath(root, SRC_ROOT)
    # tests/ stays plain-Python source: pytest loads the .pyx test files by
    # path (see Multi-AI/tests/conftest.py), so they're deliberately not compiled.
    if rel_dir.split(os.sep)[0] == "tests":
        continue
    for filename in files:
        if not filename.endswith(".pyx"):
            continue
        path = os.path.join(root, filename)
        rel = os.path.relpath(path, SRC_ROOT)          # e.g. multi_ai/models/gpt2.pyx
        module = rel[: -len(".pyx")].replace(os.sep, ".")  # -> multi_ai.models.gpt2
        extensions.append(Extension(module, [path]))

setup(
    name="Multi-AI",
    version="0.1",
    packages=["multi_ai", "multi_ai.models"],
    package_dir={"": SRC_ROOT},
    ext_modules=cythonize(extensions, compiler_directives={"language_level": "3"}),
    # A compiled extension module can't be run as a __main__ script the way
    # `python server.pyx` used to be, so the server gets a real entry point.
    entry_points={"console_scripts": ["multi-ai-server = multi_ai.server:run"]},
)
