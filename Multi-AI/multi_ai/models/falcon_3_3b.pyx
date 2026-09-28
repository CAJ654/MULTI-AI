"""Falcon3 3B: TII's efficient Falcon 3 series, sized for single-GPU/edge use."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon3-3B-Instruct"


def get_info():
    return {
        "name": "Falcon3 3B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "3B",
        "size_gb": 6.46,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License 2.0",
        "strengths": "Efficient small model tuned for reasoning, coding, and instruction-following "
        "at an edge-friendly size.",
        "speed_profile": "Fast, good intelligence for its size",
    }


if __name__ == "__main__":
    print(get_info())
