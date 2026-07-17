"""Models subpackage for multi_ai.

The model files here are plain-Python ``.pyx`` sources, which Python's import
system won't load as submodules until they're actually Cython-compiled — so
this package intentionally imports nothing. ``multi_ai.server`` loads model
files directly by file path instead (see ``_load_model_module``), and
``tests/test_imports.pyx`` validates them the same way.
"""
