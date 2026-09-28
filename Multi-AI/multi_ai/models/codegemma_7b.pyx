"""CodeGemma 7B: Google's CodeGemma 7B, served via transformers (4-bit)."""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/codegemma-7b-it"


def get_info():
    return {
        "name": "CodeGemma 7B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 17.08,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 1 7B further trained on code — instruction-tuned for code generation, explanation and chat about programming.",
        "speed_profile": "Moderate speed, good at code",
    }


if __name__ == "__main__":
    print(get_info())
