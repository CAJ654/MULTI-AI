"""MedGemma 27B: Google's MedGemma 27B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/medgemma-27b-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "MedGemma 27B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "27B",
        "size_gb": 54.82,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Multimodal MedGemma at the 27B size — strongest MedGemma for medical images and clinical reasoning. Needs CPU offload on a 12GB card. Not medical advice.",
        "speed_profile": "Slow on consumer GPUs, strong specialized medical knowledge",
    }


if __name__ == "__main__":
    print(get_info())
