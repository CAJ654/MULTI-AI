"""Gemma 3n E2B, run on-device.

On-device sibling of ``gemma3n.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-3n-E2B-it-GGUF/gemma-3n-E2B-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 3n E2B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "E2B",
        "size_gb": 3.03,
        "modality": "Text + Image + Audio",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "Natively multimodal (text, image, audio) and designed to run efficiently on-device — 'E2B' denotes ~2B effective inference cost despite more raw parameters. Q4_K_M GGUF build runs fully on-device. On-device runs the text GGUF (llama.cpp doesn't cover its audio path).",
        "speed_profile": "Fast for a multimodal model, good general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
