"""Gemma 3 27B, run on-device.

On-device sibling of ``gemma_3_27b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-3-27b-it-GGUF/gemma-3-27b-it-Q4_K_M.gguf"

# Vision projector (libmtmd) — without it the model loads and chats but
# can't see.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/gemma-3-27b-it-GGUF/mmproj-F16.gguf"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 3 27B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "27B",
        "size_gb": 16.55,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 3's flagship vision-language model. Too big for a 12GB card even at 4-bit, so expect partial CPU offload. Q4_K_M GGUF build runs fully on-device. Add ~0.86GB for its vision projector.",
        "speed_profile": "Slow on consumer GPUs, very strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
