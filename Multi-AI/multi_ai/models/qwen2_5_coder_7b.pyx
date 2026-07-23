"""Qwen2.5-Coder 7B Instruct: Alibaba's code-specialized Qwen2.5 at the 7B size."""
from __future__ import annotations

# Apache-2.0 and ungated — the official Qwen repo needs no HF login (unlike the
# gated Llama/Gemma families that use unsloth mirrors elsewhere in this roster).
_REPO_ID = "Qwen/Qwen2.5-Coder-7B-Instruct"


def get_info():
    return {
        "name": "Qwen2.5-Coder 7B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        # fp16 checkpoint size — the server loads it 4-bit, so the hardware
        # rater's server formula (size/4 × 1.15 + 1.2GB) puts it around 5.5GB.
        "size_gb": 15.2,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Code-specialized Qwen2.5 — strong at code generation, completion, "
        "reasoning, and multi-language fixing/refactoring, competitive with much larger "
        "coders. A solid default for the coding workflow.",
        "speed_profile": "Fast for a 7B, coding-focused intelligence",
    }


if __name__ == "__main__":
    print(get_info())
