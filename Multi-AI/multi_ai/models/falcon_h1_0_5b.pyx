"""Falcon-H1 0.5B: TII's hybrid Transformer+Mamba architecture at its smallest size."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon-H1-0.5B-Instruct"


def get_info():
    return {
        "name": "Falcon-H1 0.5B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "0.5B",
        "size_gb": 1.04,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "TII Falcon License (December 2024)",
        "strengths": "Hybrid Transformer+Mamba architecture at a tiny footprint — keeps the "
        "family's cheap long-context handling even at the smallest size.",
        "speed_profile": "Very fast, efficient long-context handling",
    }


if __name__ == "__main__":
    print(get_info())
