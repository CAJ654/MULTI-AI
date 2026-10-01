"""DeepSeek-R1-Distill-Qwen-32B: DeepSeek-R1 reasoning distilled into a 32B Qwen backbone."""
from __future__ import annotations

_REPO_ID = "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-32B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "32B",
        "size_gb": 65.5,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "The largest DeepSeek-R1 distill, reported to match o1-mini on several reasoning "
        "benchmarks. Too big for a 12GB card even at 4-bit, so expect partial CPU offload.",
        "speed_profile": "Slow on consumer GPUs, near-flagship reasoning",
    }


if __name__ == "__main__":
    print(get_info())
