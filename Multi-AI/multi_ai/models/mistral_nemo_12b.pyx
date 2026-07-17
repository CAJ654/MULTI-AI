"""Mistral Nemo 12B: Mistral's multilingual model co-developed with NVIDIA."""
from __future__ import annotations

_REPO_ID = "mistralai/Mistral-Nemo-Instruct-2407"


def get_info():
    return {"name": "Mistral Nemo 12B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
