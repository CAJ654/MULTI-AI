"""Llama 3 8B Instruct: Meta's Llama 3 release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/llama-3-8b-Instruct"


def get_info():
    return {
        "name": "Llama 3 8B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "8B",
        "size_gb": 16.06,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Meta Llama 3 Community License",
        "strengths": "Meta's original Llama 3 — strong general chat and instruction-following, "
        "the baseline the later 3.1/3.2 releases improved on.",
        "speed_profile": "Moderate speed, solid general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
