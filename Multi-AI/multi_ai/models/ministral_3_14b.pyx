"""Ministral 3 14B: Mistral's dense 14B edge model (Dec 2025)."""
from __future__ import annotations

# unsloth mirror: the official mistralai repo ships FP8-quantized weights,
# which need Triton FP8 kernels that don't work on Windows; this bf16 copy
# quantizes cleanly with bitsandbytes instead.
_REPO_ID = "unsloth/Ministral-3-14B-Instruct-2512"


def get_info():
    return {
        "name": "Ministral 3 14B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "14B",
        "size_gb": 27.89,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "Mistral's largest edge model — the deepest reasoning in the Ministral 3 "
        "family, at the cost of the slowest replies and biggest download.",
        "speed_profile": "Slower, deep multimodal reasoning",
    }


if __name__ == "__main__":
    print(get_info())
