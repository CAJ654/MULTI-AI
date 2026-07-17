"""Gemma 2B: Google's first-generation Gemma release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-2b-it"


def get_info():
    return {
        "name": "Gemma 2B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "2B",
        "size_gb": 5.01,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Google's first Gemma generation — solid for its size but superseded by "
        "Gemma 2/3 on most benchmarks.",
        "speed_profile": "Fast, modest intelligence",
    }


if __name__ == "__main__":
    print(get_info())
