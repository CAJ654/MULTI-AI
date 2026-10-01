"""Qwen3 4B: Alibaba's Qwen3 release at the 4B size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-4B"


def get_info():
    return {
        "name": "Qwen3 4B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "4B",
        "size_gb": 8.19,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model — the sweet spot between the tiny "
        "Qwen3 sizes and the 8B, with reasoning quality reportedly close to much larger "
        "Qwen2.5 models.",
        "speed_profile": "Fast, strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
