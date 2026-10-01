"""Qwen3 0.6B: Alibaba's Qwen3 release at the smallest, most phone-viable size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-0.6B"


def get_info():
    return {
        "name": "Qwen3 0.6B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "0.6B",
        "size_gb": 1.23,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model at a tiny footprint — can switch on "
        "step-by-step reasoning for harder prompts or answer directly for quick ones.",
        "speed_profile": "Very fast, modest but usable reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
