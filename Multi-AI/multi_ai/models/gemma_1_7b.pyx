"""Gemma 7B: Google's Gemma 7B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-7b-it"


def get_info():
    return {
        "name": "Gemma 7B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 17.08,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "The larger first-generation Gemma — clearly stronger than Gemma 1 2B, but superseded by Gemma 2 9B at a similar size.",
        "speed_profile": "Moderate speed, solid general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
