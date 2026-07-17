"""Llama 3.2 3B Instruct: Meta's Llama 3.2 at the 3B size."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/Llama-3.2-3B-Instruct"


def get_info():
    return {
        "name": "Llama 3.2 3B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "3B",
        "size_gb": 6.43,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Meta Llama 3.2 Community License",
        "strengths": "Compact Llama 3.2 tuned for edge/on-device deployment — good "
        "instruction-following for its size.",
        "speed_profile": "Fast, good intelligence for 3B",
    }


if __name__ == "__main__":
    print(get_info())
