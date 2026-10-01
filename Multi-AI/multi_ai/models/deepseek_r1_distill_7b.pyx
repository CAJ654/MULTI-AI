"""DeepSeek-R1-Distill-Qwen-7B: DeepSeek-R1 reasoning distilled into a 7B Qwen backbone."""
from __future__ import annotations

_REPO_ID = "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-7B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 15.24,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a Qwen2.5 7B backbone — "
        "noticeably stronger math and step-by-step reasoning than the 1.5B distill, still "
        "cheap to run.",
        "speed_profile": "Fast, strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
