"""Gemma 4 E2B: Google's Gemma 4 E2B, served via transformers (4-bit)."""
from __future__ import annotations

_REPO_ID = "unsloth/gemma-4-E2B-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image", "audio")


def get_info():
    return {
        "name": "Gemma 4 E2B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "E2B",
        "size_gb": 10.25,
        "modality": "Text + Image + Audio",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "Smallest Gemma 4 — natively multimodal (text, image, audio) with ~2B effective inference cost via Per-Layer Embeddings.",
        "speed_profile": "Fast for a multimodal model, good general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
