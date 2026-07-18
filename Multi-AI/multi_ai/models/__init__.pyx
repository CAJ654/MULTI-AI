"""Models subpackage for multi_ai.

The model files here are Cython-compiled to native extension modules, so they
load through the normal import system. ``multi_ai.server`` imports each one by
name (``importlib.import_module("multi_ai.models.<id>")``, see
``_load_model_module``); ``tests/test_imports.pyx`` validates them the same way.
This ``__init__`` intentionally re-exports nothing — the server discovers model
files by scanning the directory, not via package attributes.
"""
