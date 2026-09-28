"""Gemma 2 9B: Google's Gemma 2 9B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-2-9b-it"


def get_info():
    return {
        "name": "Gemma 2 9B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "9B",
        "size_gb": 18.48,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 2's mid size — a big step over the 2B on reasoning and writing, and among the strongest dense models that still fit a 12GB card at 4-bit.",
        "speed_profile": "Moderate speed, strong general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
