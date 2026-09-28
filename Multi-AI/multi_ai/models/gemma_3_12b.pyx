"""Gemma 3 12B: Google's Gemma 3 12B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3-12b-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 3 12B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "12B",
        "size_gb": 24.37,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Gemma Terms of Use",
        "strengths": "Vision-language Gemma 3 at the mid size — the strongest Gemma 3 that fits fully on a 12GB card at 4-bit, with a 128K context window.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
