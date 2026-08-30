"""Shared discovery of the Cython backend's source modules.

Both setup.py (which compiles the committed .c files) and
scripts/regen_cython.py (which regenerates those .c from the .pyx sources)
enumerate the extension modules through here, so the build and the
regeneration can't drift apart.
"""
import os

SRC_ROOT = "Multi-AI"


def iter_modules(src_root=SRC_ROOT):
    """Yield (dotted_module_name, pyx_path, c_path) for every compiled module.

    tests/ is deliberately excluded: pytest loads those .pyx files by path
    (see Multi-AI/tests/conftest.py), so they stay plain-Python source and
    are never compiled.
    """
    for root, _dirs, files in os.walk(src_root):
        rel_dir = os.path.relpath(root, src_root)
        if rel_dir.split(os.sep)[0] == "tests":
            continue
        for filename in sorted(files):
            if not filename.endswith(".pyx"):
                continue
            # Forward slashes regardless of OS: Cython copies this path
            # verbatim into each .c's metadata header, so it has to be
            # byte-identical whether the regen runs on Windows or the Linux
            # CI check — see scripts/regen_cython.py.
            pyx = os.path.join(root, filename).replace(os.sep, "/")
            rel = pyx[len(src_root.replace(os.sep, "/")) + 1 :]  # multi_ai/models/gpt2.pyx
            module = rel[: -len(".pyx")].replace("/", ".")        # -> multi_ai.models.gpt2
            c_path = pyx[: -len(".pyx")] + ".c"
            yield module, pyx, c_path
