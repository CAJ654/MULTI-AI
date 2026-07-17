"""Falcon 40B: Too large for this machine."""
from __future__ import annotations

# Not wired to a real checkpoint: 40B needs ~22GB even 4-bit-quantized, more than this machine's 12GB GPU; delete ~/.cache/huggingface/hub/models--tiiuae--falcon-40b to reclaim ~78GB of disk.
_UNSUPPORTED_REASON = "40B needs ~22GB even 4-bit-quantized, more than this machine's 12GB GPU; delete ~/.cache/huggingface/hub/models--tiiuae--falcon-40b to reclaim ~78GB of disk"


def get_info():
    return {"name": "Falcon 40B", "version": "0.1.0", "repo_id": None}


if __name__ == "__main__":
    print(get_info())
