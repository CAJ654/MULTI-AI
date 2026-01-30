# MULTI-AI
A project with multiple AI models intended to run on a backend server with a frontend made in Flutter for web or native deployment.

# Multi-AI (project)

This repository contains several small model stubs and utilities organized as a
Python package for development and testing.

Structure
- multi_ai/ - package
  - models/ - model stubs (deepmind, qwen3, etc.)
- tests/ - simple import tests

Quick start

1. Install editable package (optional):

```powershell
pip install -e .
```

2. Run a module directly:

```powershell
python -m multi_ai.models.qwen3
```

3. Run tests (pytest):

```powershell
pip install pytest
pytest -q
```
