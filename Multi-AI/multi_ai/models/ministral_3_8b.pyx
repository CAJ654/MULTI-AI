"""Ministral 3 8B: Mistral's dense 8B edge model (Dec 2025)."""
from __future__ import annotations

# unsloth mirror: the official mistralai repo ships FP8-quantized weights,
# which need Triton FP8 kernels that don't work on Windows; this bf16 copy
# quantizes cleanly with bitsandbytes instead.
_REPO_ID = "unsloth/Ministral-3-8B-Instruct-2512"


def get_info():
    return {
        "name": "Ministral 3 8B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "8B",
        "size_gb": 17.84,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Mistral's mid-size edge model — a step up in reasoning depth from the 3B "
        "variant while staying vision-capable.",
        "speed_profile": "Moderate speed, strong multimodal reasoning",
    }


if __name__ == "__main__":
    print(get_info())
