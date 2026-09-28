"""Gemma 4 12B: Google's Gemma 4 12B, served via transformers (4-bit)."""
from __future__ import annotations

_REPO_ID = "unsloth/gemma-4-12b-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image", "audio")


def get_info():
    return {
        "name": "Gemma 4 12B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "12B",
        "size_gb": 23.92,
        "modality": "Text + Image + Audio",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Dense mid-size Gemma 4 with text, image and audio input and a 256K context window. Fits a 12GB card at 4-bit.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
