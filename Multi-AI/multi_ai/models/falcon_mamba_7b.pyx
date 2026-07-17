"""FalconMamba 7B: TII's non-transformer State Space Language Model."""
from __future__ import annotations

_REPO_ID = "tiiuae/falcon-mamba-7b"


def get_info():
    return {
        "name": "FalconMamba 7B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "7B",
        "size_gb": 14.55,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "TII Falcon License 2.0",
        "strengths": "Pure state-space (Mamba) model, not a Transformer — trained at an "
        "8192-token sequence length but, unlike attention models, has no hard context cap: "
        "constant memory per token means throughput doesn't degrade on longer inputs.",
        "speed_profile": "Fast at long context, moderate raw intelligence",
    }


if __name__ == "__main__":
    print(get_info())
