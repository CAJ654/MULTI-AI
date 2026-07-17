"""Ministral 3 3B: Mistral's compact 3B edge model (Dec 2025)."""
from __future__ import annotations

# unsloth mirror: the official mistralai repo ships FP8-quantized weights,
# which need Triton FP8 kernels that don't work on Windows; this bf16 copy
# quantizes cleanly with bitsandbytes instead.
_REPO_ID = "unsloth/Ministral-3-3B-Instruct-2512"


def get_info():
    return {
        "name": "Ministral 3 3B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "3B",
        "size_gb": 7.7,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Mistral's compact edge model — vision-capable and quick, the lightest "
        "of the Ministral 3 family.",
        "speed_profile": "Fast, capable multimodal reasoning for 3B",
    }


if __name__ == "__main__":
    print(get_info())
