"""Falcon-H1 34B: TII's hybrid Transformer+Mamba architecture flagship size."""
from __future__ import annotations

_REPO_ID = "tiiuae/Falcon-H1-34B-Instruct"


def get_info():
    return {
        "name": "Falcon-H1 34B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "34B",
        "size_gb": 70.38,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "TII Falcon License (December 2024)",
        "strengths": "Falcon-H1's flagship — hybrid Transformer+Mamba quality at frontier-ish "
        "scale, with the family's cheap long-context handling. Too big for a 12GB card even "
        "at 4-bit, so expect partial CPU offload.",
        "speed_profile": "Slow on consumer GPUs, very strong general intelligence",
    }


if __name__ == "__main__":
    print(get_info())
