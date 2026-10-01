"""DeepSeek-R1-Distill-Qwen-7B, run on-device.

On-device sibling of ``deepseek_r1_distill_7b.pyx``: instead of the
transformers repo, this points at a llama.cpp GGUF quantization (Q4_K_M),
which the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-7B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B",
        "size_gb": 4.68,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a Qwen2.5 7B backbone — "
        "noticeably stronger math and step-by-step reasoning than the 1.5B distill. Q4_K_M "
        "GGUF build runs fully on-device.",
        "speed_profile": "Fast, strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
