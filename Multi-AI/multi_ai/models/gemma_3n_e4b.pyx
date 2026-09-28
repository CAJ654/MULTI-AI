"""Gemma 3n E4B: Google's Gemma 3n E4B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3n-E4B-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image", "audio")


def get_info():
    return {
        "name": "Gemma 3n E4B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "E4B",
        "size_gb": 15.7,
        "modality": "Text + Image + Audio",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "The larger Gemma 3n — natively multimodal (text, image, audio) with ~4B effective inference cost despite more raw parameters. Stronger than E2B.",
        "speed_profile": "Moderate speed, good multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
