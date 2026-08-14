"""DeepSeek V4 Flash: DeepSeek's 284B MoE model, run via a Colibri server this
app starts and supervises itself.

Same shape as glm_5_2_colibri.pyx — see that file for why this needs a third
dispatch path instead of _REPO_ID/_GGUF_SOURCE. Like Kimi K3, DeepSeek V4
Flash needs no int4 conversion — its native fp4 experts stream straight from
the official checkpoint, so _COLIBRI_REPO_ID points directly at
deepseek-ai/DeepSeek-V4-Flash-0731. The lightest of Colibri's larger
families — still well beyond transformers/llama.cpp territory here, but the
cheapest of the four 100B+ entries to actually run.
"""
from __future__ import annotations

_EXTERNAL_ENDPOINT = "colibri"
_EXTERNAL_ENDPOINT_PORT = 8010
_EXTERNAL_MIN_RAM_GB = 16.0
_EXTERNAL_RECOMMENDED_RAM_GB = 22.0
_COLIBRI_REPO_ID = "deepseek-ai/DeepSeek-V4-Flash-0731"


def get_info():
    return {
        "name": "DeepSeek V4 Flash (via Colibri)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "284B (~13B active)",
        "size_gb": 167,
        "modality": "Text",
        "context_tokens": 1_000_000,
        "license": "MIT",
        "strengths": "DeepSeek's 284B Mixture-of-Experts model run through Colibri's "
        "disk-streamed expert loading — the smallest-footprint of Colibri's 100B+ families, "
        "at ~167GB disk and 16-22GB RAM.",
        "speed_profile": "Runs via Colibri on this edge server — throughput depends on local "
        "disk speed, not this app's own generation path.",
    }


if __name__ == "__main__":
    print(get_info())
