"""Gemma 3 270M: Google's Gemma 3 270M, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3-270m-it"


def get_info():
    return {
        "name": "Gemma 3 270M",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "270M",
        "size_gb": 0.54,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "Tiny Gemma 3 built as a base for task-specific fine-tunes — handy for quick classification or extraction, weak at open-ended chat.",
        "speed_profile": "Very fast, limited intelligence",
    }


if __name__ == "__main__":
    print(get_info())
