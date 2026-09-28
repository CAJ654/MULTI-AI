"""Gemma 4 12B, run on-device.

On-device sibling of ``gemma_4_12b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-4-12b-it-GGUF/gemma-4-12b-it-Q4_K_M.gguf"

# Vision projector (libmtmd) — without it the model loads and chats but
# can't see.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/gemma-4-12b-it-GGUF/mmproj-F16.gguf"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 4 12B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "12B",
        "size_gb": 7.12,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Dense mid-size Gemma 4 with text, image and audio input and a 256K context window. Fits a 12GB card at 4-bit. Q4_K_M GGUF build runs fully on-device. Add ~0.18GB for its vision projector. Image only on-device: audio input through this projector is unverified, so use the server entry for audio.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
