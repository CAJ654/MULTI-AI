"""Falcon3 3B: TII's efficient Falcon 3 series, sized for single-GPU/edge use."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon3-3B-Instruct"


def get_info():
    return {"name": "Falcon3 3B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
