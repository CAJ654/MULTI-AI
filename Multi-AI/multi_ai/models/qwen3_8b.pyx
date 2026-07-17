"""Qwen3 8B: Alibaba's Qwen3 release at the 8B size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-8B"


def get_info():
    return {
        "name": "Qwen3 8B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "8B",
        "size_gb": 16.38,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model — can switch on step-by-step reasoning "
        "for hard problems or answer directly for quick ones.",
        "speed_profile": "Moderate speed, strong reasoning (hybrid think mode)",
    }


if __name__ == "__main__":
    print(get_info())
