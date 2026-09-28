"""MedGemma 27B Text: Google's MedGemma 27B Text, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/medgemma-27b-text-it"


def get_info():
    return {
        "name": "MedGemma 27B Text",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "27B",
        "size_gb": 54.82,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Text-only MedGemma 27B, tuned for clinical text reasoning (EHRs, medical QA). Needs CPU offload on a 12GB card. Not medical advice.",
        "speed_profile": "Slow on consumer GPUs, strong specialized medical knowledge",
    }


if __name__ == "__main__":
    print(get_info())
