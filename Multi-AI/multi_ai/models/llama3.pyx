"""Llama 3 8B Instruct: Meta's Llama 3 release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/llama-3-8b-Instruct"


def get_info():
    return {"name": "Llama 3 8B Instruct", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
