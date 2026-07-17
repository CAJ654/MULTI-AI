"""Gemma 3 4B: Google's Gemma 3 at the 4B size."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3-4b-it"


def get_info():
    return {
        "name": "Gemma 3 4B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "4B",
        "size_gb": 8.6,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Gemma Terms of Use",
        "strengths": "Vision-language Gemma 3 — handles image understanding alongside text, "
        "with a long 128K context window.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
