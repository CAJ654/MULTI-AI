"""Gemma 3 27B: Google's Gemma 3 27B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3-27b-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 3 27B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "27B",
        "size_gb": 54.82,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 3's flagship vision-language model. Too big for a 12GB card even at 4-bit, so expect partial CPU offload.",
        "speed_profile": "Slow on consumer GPUs, very strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())
