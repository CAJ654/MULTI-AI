"""GPT-OSS 20B: OpenAI's open-weight 20B reasoning model, run on-device.

Not served via transformers: that path dequantizes the MXFP4 checkpoint to
bf16 (~40GB), more than this machine's RAM. llama.cpp runs the native MXFP4
GGUF (~12.8GB, only ~3.6B active params per token), so the Flutter app runs
it locally through llamadart instead.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://ggml-org/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf"


def get_info():
    return {
        "name": "GPT-OSS 20B",
        "version": "0.1.0",
        "repo_id": None,
        "params": "20B",
        "size_gb": 12.11,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "OpenAI's open-weight reasoning model — Mixture-of-Experts with only ~3.6B "
        "active parameters per token, so it reasons like a much bigger model while staying fast.",
        "speed_profile": "Fast for its reasoning quality (sparse MoE), large download",
    }


if __name__ == "__main__":
    print(get_info())
