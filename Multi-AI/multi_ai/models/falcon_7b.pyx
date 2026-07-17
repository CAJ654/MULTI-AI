"""Falcon 7B Instruct: TII's first-generation model, instruction-tuned variant."""
from __future__ import annotations

_REPO_ID = "tiiuae/falcon-7b-instruct"


def get_info():
    return {
        "name": "Falcon 7B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 14.5,
        "modality": "Text",
        "context_tokens": 2048,
        "license": "Apache 2.0",
        "strengths": "TII's original instruction-tuned Falcon — capable general chat, but its "
        "config declares no fixed context cap and it was trained at a short 2048-token "
        "sequence length, which limits long conversations.",
        "speed_profile": "Moderate speed, dated but competent",
    }


if __name__ == "__main__":
    print(get_info())
