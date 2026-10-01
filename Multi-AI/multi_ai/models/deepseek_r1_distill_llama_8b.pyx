"""DeepSeek-R1-Distill-Llama-8B: DeepSeek-R1 reasoning distilled into a Llama 3.1 8B backbone."""
from __future__ import annotations

_REPO_ID = "deepseek-ai/DeepSeek-R1-Distill-Llama-8B"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Llama-8B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "8B",
        "size_gb": 16.06,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a Llama 3.1 8B backbone "
        "instead of Qwen — a different base-model flavor of the same reasoning distillation, "
        "strong on math and step-by-step logic.",
        "speed_profile": "Fast, strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
