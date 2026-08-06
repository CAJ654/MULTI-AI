"""OLMoE: AI2's 7B MoE model, run via a user-run Colibri server.

Same _EXTERNAL_ENDPOINT shape as glm_5_2_colibri.pyx, included because it's
one of Colibri's five supported families — but at 7B total/1B active it's
far smaller than Colibri's other entries, and would likely run through the
existing _REPO_ID/_GGUF_SOURCE paths just as well. It's here for completeness
of Colibri support, not because this is the only way to run it.
"""
from __future__ import annotations

_EXTERNAL_ENDPOINT = "colibri"
_EXTERNAL_ENDPOINT_PORT = 8010
_EXTERNAL_MIN_RAM_GB = 8.0
_EXTERNAL_RECOMMENDED_RAM_GB = 8.0


def get_info():
    return {
        "name": "OLMoE (via Colibri)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B (~1B active)",
        "size_gb": 4,
        "modality": "Text",
        "context_tokens": 4096,
        "license": "Apache 2.0 (instruct variant also carries Gemma Terms of Use, "
        "inherited from its RLHF/DPO training data)",
        "strengths": "AI2's fully open 7B Mixture-of-Experts model run through Colibri — by "
        "far the smallest and cheapest of Colibri's supported families to try.",
        "speed_profile": "Runs via Colibri on this edge server — throughput depends on local "
        "disk speed, not this app's own generation path.",
    }


if __name__ == "__main__":
    print(get_info())
