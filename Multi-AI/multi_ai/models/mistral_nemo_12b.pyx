"""Mistral Nemo 12B: Mistral's multilingual model co-developed with NVIDIA."""
from __future__ import annotations

_REPO_ID = "mistralai/Mistral-Nemo-Instruct-2407"


def get_info():
    return {
        "name": "Mistral Nemo 12B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "12B",
        "size_gb": 24.5,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "Mistral's multilingual model co-developed with NVIDIA — strong across "
        "non-English languages with a large 128K context window.",
        "speed_profile": "Moderate speed, strong multilingual intelligence",
    }


if __name__ == "__main__":
    print(get_info())
