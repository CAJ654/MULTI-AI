"""CodeGemma 2B: Google's CodeGemma 2B, served via transformers (4-bit).

Unlike the 7B, the 2B release is base-only (pretrained for code completion,
not instruction-tuned) — there's no ``-it`` variant.
"""
from __future__ import annotations

# unsloth mirror: the official repo is gated (needs HF login + license acceptance).
_REPO_ID = "unsloth/codegemma-2b"


def get_info():
    return {
        "name": "CodeGemma 2B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "2B",
        "size_gb": 4.89,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 1 2B further trained on code — base pretrained model tuned for fast "
        "fill-in-the-middle code completion rather than chat.",
        "speed_profile": "Very fast, code-completion focused",
    }


if __name__ == "__main__":
    print(get_info())
