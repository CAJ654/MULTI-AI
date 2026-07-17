"""Llama 3.2 1B Instruct: Meta's smallest Llama 3.2 text model."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/Llama-3.2-1B-Instruct"


def get_info():
    return {"name": "Llama 3.2 1B Instruct", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
