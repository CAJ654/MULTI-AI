"""Gemma 3n E2B: Google's Gemma 3n, optimized for low-resource/on-device use."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/gemma-3n-E2B-it"


def get_info():
    return {
        "name": "Gemma 3n E2B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "E2B",
        "size_gb": 10.88,
        "modality": "Text + Image + Audio",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "Natively multimodal (text, image, audio) and designed to run efficiently "
        "on-device — 'E2B' denotes ~2B effective inference cost despite more raw parameters.",
        "speed_profile": "Fast for a multimodal model, good general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
