"""Gemma 4 26B A4B, run on-device.

On-device sibling of ``gemma_4_26b_a4b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"

# Vision projector (libmtmd) — without it the model loads and chats but
# can't see.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/gemma-4-26B-A4B-it-GGUF/mmproj-F16.gguf"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 4 26B A4B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "26B",
        "size_gb": 16.95,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Mixture-of-experts Gemma 4 — 26B total but only ~4B active per token, so it runs far faster than its size suggests once offloaded. Text + image, 256K context. Q4_K_M GGUF build runs fully on-device. Add ~1.19GB for its vision projector.",
        "speed_profile": "Moderate speed with offload, very strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
