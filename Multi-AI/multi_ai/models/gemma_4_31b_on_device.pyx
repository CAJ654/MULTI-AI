"""Gemma 4 31B, run on-device.

On-device sibling of ``gemma_4_31b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf"

# Vision projector (libmtmd) — without it the model loads and chats but
# can't see.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/gemma-4-31B-it-GGUF/mmproj-F16.gguf"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 4 31B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "31B",
        "size_gb": 18.32,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Gemma 4's dense flagship — the most capable Gemma. Text + image, 256K context. Far beyond a 12GB card, so expect heavy CPU offload. Q4_K_M GGUF build runs fully on-device. Add ~1.2GB for its vision projector.",
        "speed_profile": "Slow on consumer GPUs, frontier-class open intelligence",
    }


if __name__ == "__main__":
    print(get_info())
