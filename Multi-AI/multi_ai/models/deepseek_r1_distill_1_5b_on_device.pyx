"""DeepSeek-R1-Distill-Qwen-1.5B: DeepSeek-R1 reasoning distilled into a 1.5B Qwen backbone, run on-device.

On-device sibling of ``deepseek_r1_distill_1_5b.pyx``: instead of the
transformers repo, this points at a llama.cpp GGUF quantization (Q4_K_M),
which the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-1.5B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "1.5B",
        "size_gb": 1.12,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a small Qwen2.5 backbone — "
        "punches well above its size on math and step-by-step reasoning. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Fast, surprisingly strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
