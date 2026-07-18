"""FalconMamba 7B, run on-device.

On-device sibling of ``falcon_mamba_7b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/falcon-mamba-7b-instruct-Q4_K_M-GGUF/falcon-mamba-7B-instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "FalconMamba 7B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B",
        "size_gb": 4.2,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "TII Falcon License 2.0",
        "strengths": "Pure state-space (Mamba) model, not a Transformer — trained at an 8192-token sequence length but, unlike attention models, has no hard context cap: constant memory per token means throughput doesn't degrade on longer inputs. Q4_K_M GGUF build runs fully on-device. Note: the on-device build is the instruct-tuned FalconMamba (the server sibling runs the base model).",
        "speed_profile": "Fast at long context, moderate raw intelligence",
    }


if __name__ == "__main__":
    print(get_info())
