"""Gemma 2 27B: Google's Gemma 2 27B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-2-27b-it"


def get_info():
    return {
        "name": "Gemma 2 27B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "27B",
        "size_gb": 54.46,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 2's flagship — near the top of open models of its generation. Too big for a 12GB card even at 4-bit, so expect partial CPU offload.",
        "speed_profile": "Slow on consumer GPUs, very strong general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
