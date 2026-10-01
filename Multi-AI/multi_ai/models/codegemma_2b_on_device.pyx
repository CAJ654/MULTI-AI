"""CodeGemma 2B, run on-device.

On-device sibling of ``codegemma_2b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/codegemma-2b-GGUF/codegemma-2b-Q4_K_M.gguf"


def get_info():
    return {
        "name": "CodeGemma 2B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "2B",
        "size_gb": 1.52,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 1 2B further trained on code — base pretrained model tuned for fast "
        "fill-in-the-middle code completion rather than chat. Q4_K_M GGUF build runs fully "
        "on-device.",
        "speed_profile": "Very fast, code-completion focused",
    }


if __name__ == "__main__":
    print(get_info())
