"""Falcon-H1 1.5B: TII's hybrid Transformer+Mamba architecture model."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon-H1-1.5B-Instruct"


def get_info():
    return {"name": "Falcon-H1 1.5B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
