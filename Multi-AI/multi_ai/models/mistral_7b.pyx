"""Mistral 7B Instruct: Mistral AI's original efficient 7B foundation model."""
from __future__ import annotations

_REPO_ID = "mistralai/Mistral-7B-Instruct-v0.3"


def get_info():
    return {
        "name": "Mistral 7B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 14.5,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Mistral AI's original efficient 7B — a strong, well-rounded generalist "
        "that helped popularize small-but-capable open models.",
        "speed_profile": "Moderate speed, solid general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
