"""CodeGemma 7B, run on-device.

On-device sibling of ``codegemma_7b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/codegemma-7b-it-GGUF/codegemma-7b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "CodeGemma 7B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B",
        "size_gb": 5.33,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 1 7B further trained on code — instruction-tuned for code generation, explanation and chat about programming. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, good at code",
    }


if __name__ == "__main__":
    print(get_info())
