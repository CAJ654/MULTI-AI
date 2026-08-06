"""Inkling: Thinking Machines' 975B MoE model, run via a user-run Colibri server.

Same shape as glm_5_2_colibri.pyx — see that file for why this needs a third
dispatch path instead of _REPO_ID/_GGUF_SOURCE. Colibri's own docs (docs/inkling.md)
note the process needs at least ~64GB RAM to avoid dying mid-generation; below
that, an int4-dense-container mode fits a 25GB box but is disk-bound (tens of
seconds per token) rather than genuinely usable, so this file rates against the
64GB/120GB tiers rather than that fallback mode's 25GB floor.
"""
from __future__ import annotations

_EXTERNAL_ENDPOINT = "colibri"
_EXTERNAL_ENDPOINT_PORT = 8010
_EXTERNAL_MIN_RAM_GB = 64.0
_EXTERNAL_RECOMMENDED_RAM_GB = 120.0


def get_info():
    return {
        "name": "Inkling (via Colibri)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "975B (~41B active)",
        "size_gb": 469,
        "modality": "Text",
        "context_tokens": 1_000_000,
        "license": "Apache 2.0",
        "strengths": "Thinking Machines' 975B MoE model run through Colibri's disk-streamed "
        "expert loading. Wants real RAM headroom — under ~64GB the process dies mid-run; a "
        "25GB int4-dense-container mode exists but is disk-bound and impractically slow.",
        "speed_profile": "Runs via Colibri on this edge server — throughput depends on local "
        "disk speed, not this app's own generation path.",
    }


if __name__ == "__main__":
    print(get_info())
