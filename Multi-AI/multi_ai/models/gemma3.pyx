"""Gemma 3 1B: Google's third-generation Gemma release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3-1b-it"


def get_info():
    return {"name": "Gemma 3 1B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
