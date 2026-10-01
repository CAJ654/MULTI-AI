"""Falcon-H1 7B: TII's hybrid Transformer+Mamba architecture at the 7B size."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon-H1-7B-Instruct"


def get_info():
    return {
        "name": "Falcon-H1 7B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 14.49,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "TII Falcon License 2.0",
        "strengths": "Hybrid Transformer+Mamba architecture — combines attention quality with "
        "state-space efficiency, so long-context handling stays cheap even at 7B.",
        "speed_profile": "Fast, efficient long-context handling",
    }


if __name__ == "__main__":
    print(get_info())
