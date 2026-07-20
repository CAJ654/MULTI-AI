"""Gemma 4 E4B: Google's on-device Gemma 4 at the larger effective size.

Larger sibling of ``gemma4_e2b_on_device.pyx`` — same omni GGUF shape and the
same three input modalities, trading ~1.9GB of extra weights for more capability.
See that file for why Gemma 4 rather than Gemma 3n. GGUF-only, no ``_REPO_ID``.

Desktop-comfortable rather than phone-viable: 4.98GB of weights plus a ~0.99GB
projector is close to what the E2B build asks for in total, and wave-0
verification showed 6.85GB still full-offloading on a 12GB card.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf"

# Omni projector — image and audio both, same as the E2B build.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/gemma-4-E4B-it-GGUF/mmproj-F16.gguf"
_INPUT_MODALITIES = ("text", "image", "audio")


def get_info():
    return {
        "name": "Gemma 4 E4B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "E4B",
        "size_gb": 4.98,
        "modality": "Text + Image + Audio",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "Fully multimodal on-device — image and audio input both run through "
        "llama.cpp with no server. 'E4B' denotes ~4B effective inference cost via Per-Layer "
        "Embeddings; stronger than the E2B build at roughly 1.9GB more weights, and better "
        "suited to desktop than to a phone. Add ~0.99GB for its projector.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
