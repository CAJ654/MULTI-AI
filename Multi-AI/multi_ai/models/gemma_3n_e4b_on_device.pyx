"""Gemma 3n E4B, run on-device.

On-device sibling of ``gemma_3n_e4b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-3n-E4B-it-GGUF/gemma-3n-E4B-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 3n E4B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "E4B",
        "size_gb": 4.54,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "The larger Gemma 3n — natively multimodal (text, image, audio) with ~4B effective inference cost despite more raw parameters. Stronger than E2B. Q4_K_M GGUF build runs fully on-device. Text only here: llama.cpp has no projector for Gemma 3n's vision/audio towers — use the server entry for image and audio input.",
        "speed_profile": "Moderate speed, good multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
