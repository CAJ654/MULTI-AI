"""Falcon3 1B: TII's efficient Falcon 3 series at its smallest, most phone-viable size."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon3-1B-Instruct"


def get_info():
    return {
        "name": "Falcon3 1B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "1B",
        "size_gb": 2.15,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License (December 2024)",
        "strengths": "The smallest Falcon 3 size — instruction-following and basic reasoning "
        "tuned into a footprint light enough for constrained hardware.",
        "speed_profile": "Very fast, modest intelligence for its tiny size",
    }


if __name__ == "__main__":
    print(get_info())
