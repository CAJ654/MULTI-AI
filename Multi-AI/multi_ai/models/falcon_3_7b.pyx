"""Falcon3 7B: TII's efficient Falcon 3 series at the 7B size."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon3-7B-Instruct"


def get_info():
    return {
        "name": "Falcon3 7B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 15.07,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License (December 2024)",
        "strengths": "Mid-size Falcon 3 — stronger reasoning, coding, and instruction-following "
        "than the 3B while still comfortably single-GPU friendly.",
        "speed_profile": "Fast, good general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
