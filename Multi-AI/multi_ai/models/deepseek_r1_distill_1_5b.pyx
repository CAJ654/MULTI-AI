"""DeepSeek-R1-Distill-Qwen-1.5B: DeepSeek-R1 reasoning distilled into a 1.5B Qwen backbone."""
from __future__ import annotations

_REPO_ID = "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-1.5B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "1.5B",
        "size_gb": 3.55,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a small Qwen2.5 backbone — "
        "punches well above its size on math and step-by-step reasoning.",
        "speed_profile": "Fast, surprisingly strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
