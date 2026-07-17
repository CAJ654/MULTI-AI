"""Kimi Instant Edge: Not wired up."""
from __future__ import annotations

# Not wired to a real checkpoint: no standalone small 'edge' checkpoint exists publicly — the real Kimi K2.6 is a ~1 trillion parameter MoE model.
_UNSUPPORTED_REASON = "no standalone small 'edge' checkpoint exists publicly — the real Kimi K2.6 is a ~1 trillion parameter MoE model"


def get_info():
    return {"name": "Kimi Instant Edge", "version": "0.1.0", "repo_id": None}


if __name__ == "__main__":
    print(get_info())
