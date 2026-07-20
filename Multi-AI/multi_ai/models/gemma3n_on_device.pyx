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
        # Text, despite the checkpoint being natively multimodal — this field
        # describes what *this* entry can do, and llama.cpp has no projector for
        # Gemma 3n's MobileNet-V5 vision or USM audio towers (no mmproj exists in
        # any GGUF repo, and Gemma 3n is absent from llama.cpp's supported
        # multimodal list). Saying otherwise advertised capability the app then
        # correctly refused to enable. See _strengths below for where to go
        # instead; Gemma 4 E2B/E4B is the on-device multimodal option.
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "Designed to run efficiently on-device — 'E2B' denotes ~2B effective "
        "inference cost despite more raw parameters. Q4_K_M GGUF build runs fully on-device. "
        "Text only here: the checkpoint is natively multimodal, but llama.cpp runs just its "
        "text path — pick the server-backed 'Gemma 3n E2B' entry for image and audio input.",
        "speed_profile": "Fast for a multimodal model, good general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
