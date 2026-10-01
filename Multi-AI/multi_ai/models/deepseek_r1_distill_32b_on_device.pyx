"""DeepSeek-R1-Distill-Qwen-32B, run on-device.

On-device sibling of ``deepseek_r1_distill_32b.pyx``: instead of the
transformers repo, this points at a llama.cpp GGUF quantization (Q4_K_M),
which the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "DeepSeek-R1-Distill-Qwen-32B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "32B",
        "size_gb": 19.85,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "MIT",
        "strengths": "The largest DeepSeek-R1 distill, reported to match o1-mini on several "
        "reasoning benchmarks. Q4_K_M GGUF build runs fully on-device, though still a heavy "
        "download and needs real RAM/VRAM headroom.",
        "speed_profile": "Slow, near-flagship reasoning",
    }


if __name__ == "__main__":
    print(get_info())
