"""DeepSeek-R1-Distill-Qwen-14B: DeepSeek-R1 reasoning distilled into a 14B Qwen backbone."""
from __future__ import annotations

_REPO_ID = "deepseek-ai/DeepSeek-R1-Distill-Qwen-14B"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-14B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "14B",
        "size_gb": 29.54,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a Qwen2.5 14B backbone — "
        "closes much of the gap to full R1 on math and coding benchmarks while staying "
        "runnable on a single card at 4-bit.",
        "speed_profile": "Moderate speed, very strong reasoning",
    }


if __name__ == "__main__":
    print(get_info())
