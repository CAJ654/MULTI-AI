"""Qwen3 14B: Alibaba's Qwen3 release at the 14B size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-14B"


def get_info():
    return {
        "name": "Qwen3 14B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "14B",
        "size_gb": 28.67,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model — a large step up in reasoning quality "
        "over the 8B, competitive with much bigger dense models on hard benchmarks.",
        "speed_profile": "Moderate speed, very strong reasoning",
    }


if __name__ == "__main__":
    print(get_info())
