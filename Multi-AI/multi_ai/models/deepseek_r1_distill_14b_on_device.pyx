"""DeepSeek-R1-Distill-Qwen-14B, run on-device.

On-device sibling of ``deepseek_r1_distill_14b.pyx``: instead of the
transformers repo, this points at a llama.cpp GGUF quantization (Q4_K_M),
which the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF/DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-14B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "14B",
        "size_gb": 8.99,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a Qwen2.5 14B backbone — "
        "closes much of the gap to full R1 on math and coding benchmarks. Q4_K_M GGUF build "
        "runs fully on-device.",
        "speed_profile": "Moderate speed, very strong reasoning",
    }


if __name__ == "__main__":
    print(get_info())
