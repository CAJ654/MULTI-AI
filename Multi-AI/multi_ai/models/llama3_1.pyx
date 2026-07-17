"""Llama 3.1 8B Instruct: Meta's Llama 3.1 release."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/Meta-Llama-3.1-8B-Instruct"


def get_info():
    return {
        "name": "Llama 3.1 8B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "8B",
        "size_gb": 16.06,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Meta Llama 3.1 Community License",
        "strengths": "Extends Llama 3 with a 128K context window and better multilingual and "
        "tool-use performance.",
        "speed_profile": "Moderate speed, strong general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
