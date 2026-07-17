"""Falcon2 11B: TII's multilingual, multimodal-capable Falcon 2 release."""
from __future__ import annotations

_REPO_ID = "tiiuae/falcon-11B"


def get_info():
    return {
        "name": "Falcon2 11B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "11B",
        "size_gb": 22.21,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "TII Falcon License 2.0",
        "strengths": "TII's multilingual generalist — decent breadth across languages for a "
        "mid-size dense model.",
        "speed_profile": "Moderate speed, solid general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
