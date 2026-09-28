"""Gemma 4 26B A4B: Google's Gemma 4 26B A4B, served via transformers (4-bit)."""
from __future__ import annotations

_REPO_ID = "unsloth/gemma-4-26B-A4B-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 4 26B A4B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "26B",
        "size_gb": 51.61,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Mixture-of-experts Gemma 4 — 26B total but only ~4B active per token, so it runs far faster than its size suggests once offloaded. Text + image, 256K context.",
        "speed_profile": "Moderate speed with offload, very strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
