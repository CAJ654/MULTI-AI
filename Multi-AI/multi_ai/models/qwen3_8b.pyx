"""Qwen3 8B: Alibaba's Qwen3 release at the 8B size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-8B"


def get_info():
    return {"name": "Qwen3 8B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
