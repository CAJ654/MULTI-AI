"""Mixtral 8x7B: Too large for this machine."""
from __future__ import annotations

# Not wired to a real checkpoint: MoE with ~47B total parameters needs ~24GB even 4-bit-quantized, more than this machine's 12GB GPU.
_UNSUPPORTED_REASON = "MoE with ~47B total parameters needs ~24GB even 4-bit-quantized, more than this machine's 12GB GPU"


def get_info():
    return {"name": "Mixtral 8x7B", "version": "0.1.0", "repo_id": None}


if __name__ == "__main__":
    print(get_info())
