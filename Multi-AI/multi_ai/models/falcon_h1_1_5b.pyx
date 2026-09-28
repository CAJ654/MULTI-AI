"""Falcon-H1 1.5B: TII's hybrid Transformer+Mamba architecture model."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon-H1-1.5B-Instruct"


def get_info():
    return {
        "name": "Falcon-H1 1.5B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "1.5B",
        "size_gb": 3.11,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "TII Falcon License 2.0",
        "strengths": "Hybrid Transformer+Mamba architecture — combines attention quality with "
        "state-space efficiency, so it handles very long context cheaply.",
        "speed_profile": "Fast, efficient long-context handling",
    }


if __name__ == "__main__":
    print(get_info())
