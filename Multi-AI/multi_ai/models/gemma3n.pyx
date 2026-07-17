"""Gemma 3n E2B: Google's Gemma 3n, optimized for low-resource/on-device use."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3n-E2B-it"


def get_info():
    return {"name": "Gemma 3n E2B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())
