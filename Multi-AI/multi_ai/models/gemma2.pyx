"""Gemma 2 2B: Google's second-generation Gemma release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-2-2b-it"


def get_info():
    return {"name": "Gemma 2 2B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
