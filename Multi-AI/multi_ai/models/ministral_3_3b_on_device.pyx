"""Ministral 3 3B: Mistral's compact 3B edge model (Dec 2025), run on-device.

On-device sibling of ``ministral_3_3b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://mistralai/Ministral-3-3B-Instruct-2512-GGUF/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf"

# Vision needs llama.cpp's multimodal projector (libmtmd), which ships as a
# second GGUF alongside the text weights. BF16 rather than the F16 used by the
# other Ministrals: this repo (mistralai's own, not the unsloth mirror) ships
# only that one, and a projector from the same conversion as the text weights
# is worth more than matching float layouts across the roster.
_GGUF_MMPROJ_SOURCE = (
    "hf://mistralai/Ministral-3-3B-Instruct-2512-GGUF/Ministral-3-3B-Instruct-2512-BF16-mmproj.gguf"
)
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Ministral 3 3B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "3B",
        "size_gb": 2.15,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Mistral's compact edge model — vision-capable and quick, the lightest "
        "of the Ministral 3 family. Q4_K_M GGUF build plus its F16 projector run fully "
        "on-device, so image input works with no server and no network.",
        "speed_profile": "Fast, capable multimodal reasoning for 3B",
    }


if __name__ == "__main__":
    print(get_info())
