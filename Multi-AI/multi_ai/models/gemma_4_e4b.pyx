"""Gemma 4 E4B: Google's Gemma 4 E4B, served via transformers (4-bit)."""
from __future__ import annotations

_REPO_ID = "unsloth/gemma-4-E4B-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image", "audio")


def get_info():
    return {
        "name": "Gemma 4 E4B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "E4B",
        "size_gb": 15.99,
        "modality": "Text + Image + Audio",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "Gemma 4 at ~4B effective size — natively multimodal (text, image, audio), stronger than E2B at a modest cost.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
