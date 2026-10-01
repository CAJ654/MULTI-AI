"""DeepSeek-R1-Distill-Llama-8B, run on-device.

On-device sibling of ``deepseek_r1_distill_llama_8b.pyx``: instead of the
transformers repo, this points at a llama.cpp GGUF quantization (Q4_K_M),
which the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF/DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Llama-8B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "8B",
        "size_gb": 4.92,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "Distilled from DeepSeek-R1's reasoning traces onto a Llama 3.1 8B backbone "
        "instead of Qwen — a different base-model flavor of the same reasoning distillation. "
        "Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Fast, strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())
