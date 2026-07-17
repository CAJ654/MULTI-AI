"""Gemma 3 1B: Google's third-generation Gemma release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3-1b-it"


def get_info():
    return {
        "name": "Gemma 3 1B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "1B",
        "size_gb": 2.0,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "Smallest Gemma 3 — tuned for on-device/edge use with a much longer "
        "context window than earlier Gemma generations.",
        "speed_profile": "Very fast, lighter intelligence",
    }


if __name__ == "__main__":
    print(get_info())
