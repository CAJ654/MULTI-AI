"""Gemma 3 12B, run on-device.

On-device sibling of ``gemma_3_12b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-3-12b-it-GGUF/gemma-3-12b-it-Q4_K_M.gguf"

# Vision projector (libmtmd) — without it the model loads and chats but
# can't see.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/gemma-3-12b-it-GGUF/mmproj-F16.gguf"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 3 12B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "12B",
        "size_gb": 7.3,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Gemma Terms of Use",
        "strengths": "Vision-language Gemma 3 at the mid size — the strongest Gemma 3 that fits fully on a 12GB card at 4-bit, with a 128K context window. Q4_K_M GGUF build runs fully on-device. Add ~0.85GB for its vision projector.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
