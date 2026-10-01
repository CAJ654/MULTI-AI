"""Falcon3 10B: TII's efficient Falcon 3 series flagship dense size."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon3-10B-Instruct"


def get_info():
    return {
        "name": "Falcon3 10B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "10B",
        "size_gb": 21.53,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License 2.0",
        "strengths": "Falcon 3's largest dense model — best reasoning and coding quality in the "
        "family, upscaled from the 7B via depth expansion and further training.",
        "speed_profile": "Moderate speed, strongest Falcon 3 intelligence",
    }


if __name__ == "__main__":
    print(get_info())
