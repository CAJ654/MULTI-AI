"""Gemma 2B: Google's first-generation Gemma release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-2b-it"


def get_info():
    return {"name": "Gemma 2B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
