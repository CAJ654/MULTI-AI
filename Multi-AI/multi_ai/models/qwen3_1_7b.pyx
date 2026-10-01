"""Qwen3 1.7B: Alibaba's Qwen3 release at the 1.7B size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-1.7B"


def get_info():
    return {
        "name": "Qwen3 1.7B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "1.7B",
        "size_gb": 3.48,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model — can switch on step-by-step reasoning "
        "for hard problems or answer directly for quick ones, with more headroom than the "
        "0.6B entry.",
        "speed_profile": "Very fast, solid reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
