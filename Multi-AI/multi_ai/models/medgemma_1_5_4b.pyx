"""MedGemma 1.5 4B: Google's MedGemma 1.5 4B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/medgemma-1.5-4b-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "MedGemma 1.5 4B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "4B",
        "size_gb": 8.6,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Updated MedGemma 4B with improved medical image and text understanding. A research tool, not medical advice.",
        "speed_profile": "Moderate speed, specialized medical knowledge",
    }


if __name__ == "__main__":
    print(get_info())
