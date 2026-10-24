# Which models work with the Code tab

The Code tab needs a model that emits **real tool calls** — the structured
`tool_calls` an agent loop acts on — not a description of one in prose. This is
a property of how a model was *trained* and what chat template ships with it, not
of its size or its name. Measured 2026-10-24; all 68 roster models are covered.

## How this was determined

- **Tested** — the model was run under real `llama-server` (llama.cpp b11193,
  `--jinja`, the way the app starts it) and sent the same request five times: a
  system prompt, "read the file hello.txt", and two tools (`read`, `bash`). A
  sample counts only if the reply came back as a real `tool_calls` entry, not
  text that looks like a call. Gemma 4 E2B was also run end to end through
  opencode (`app/test/real_code_run_test.dart`) and read a file correctly.
- **Template check** — for every repo, the published chat template was read and
  checked for tool support and format. This is *necessary but not sufficient*:
  Qwen2.5-Coder's template renders tools, yet the model fails.
- **Inferred** — untested models are placed by their family: same recipe and
  template as a tested sibling. Treat these as predictions; a 1B result does not
  guarantee an 8B one, nor the reverse.

Small models are less reliable than large ones, so a tested pass at 0.6B–3B is a
good sign for the bigger siblings, while a fail at a small size is weaker
evidence about the large ones.

## Works (tested)

| Model | Result | Note |
|---|---|---|
| `qwen3_0_6b` | 5/5 | Qwen3 is trained for tool calls (`<tool_call>` format) |
| `qwen3_1_7b` | 5/5 | |
| `gemma_4_e2b` | 5/5 | Also verified end to end through opencode |
| `ministral_3_3b` | 5/5 | Mistral-style tool calls |
| `falcon_3_1b` | 4/5 | Flaky: one sample wrote an empty `<tool_call>` tag as text |

## Should work (not tested)

| Models | Why |
|---|---|
| `qwen3_4b`, `qwen3_8b`, `qwen3_14b`, `qwen3_32b`, `qwen3_30b_a3b` | Same family and template as the tested Qwen3 |
| `gemma_4_e4b`, `gemma_4_12b`, `gemma_4_26b_a4b`, `gemma_4_31b` | Same template as the tested Gemma 4 E2B |
| `ministral_3_8b`, `ministral_3_14b` | Same family as the tested Ministral 3B |
| `mistral_7b`, `mistral_nemo_12b` | Mistral tool template (`[TOOL_CALLS]`); older, but built for it |
| `llama_3_2_3b`, `llama_3_1_8b` | Llama 3.1+ tool format. The 1B is flaky (below), so expect the 3B to be better but not perfect |
| `falcon_3_3b`, `falcon_3_7b`, `falcon_3_10b` | Same family as Falcon3 1B (4/5); expect occasional misses |
| `gpt_oss_20b` | Native tool calling, but 12.1 GB — too big for a 12 GB card without offloading |

## Uncertain

| Model | Why |
|---|---|
| `llama_3_2_1b` | Tested and unreliable: two samples returned real calls with mangled arguments (`{"properties": {...}}`), then llama-server answered 500 "output does not match the expected format" |
| `qwen2_5_coder_14b`, `qwen2_5_coder_32b` | The family fails at 1.5B and 7B; the larger two are untested and may or may not behave better |
| `falcon_h1_1_5b`, `falcon_h1_3b`, `falcon_h1_7b`, `falcon_h1_34b` | The 0.5B fails (below); the others are untested |

## Should not work

| Models | Tested? | Why |
|---|---|---|
| `qwen2_5_coder_0_5b`, `_1_5b`, `_3b`, `_7b` | 1.5B: 0/5; 7B: 0/4 direct plus a failed full run | The Coder fine-tune loses the tool-call format. The plain Qwen2.5-0.5B-Instruct (not in the roster) gets 5/5, so this is the Coder training, not the base model |
| `falcon_h1_0_5b` | 0/5 | Writes correct-looking JSON as text; llama.cpp doesn't recognise it as a call |
| `deepseek_r1_distill_1_5b`, `_7b`, `_14b`, `_32b`, `_llama_8b` | 1.5B: 0/5 | R1 distills aren't trained for function calling; it says it can't read files |
| `gemma_3_270m`, `_1b`, `_4b`, `_12b`, `_27b` | 1B: 0/5 | Template has no tool support. The 1B **invents file contents** and claims it read the file |
| `gemma_3n_e2b`, `gemma_3n_e4b` | no | No tool support in the template |
| `gemma_1_2b`, `gemma_1_7b`, `gemma_2_2b`, `gemma_2_9b`, `gemma_2_27b` | no | No tool support in the template |
| `medgemma_4b`, `medgemma_1_5_4b`, `medgemma_27b`, `medgemma_27b_text` | no | Gemma 3 lineage, no tool support |
| `txgemma_2b`, `txgemma_9b`, `txgemma_27b` | no | Gemma lineage, no tool support (template is in a gated repo, so not read) |
| `codegemma_2b`, `codegemma_7b` | 2B: 0/5 | Code-completion model, no chat/tool template |
| `recurrentgemma_2b`, `recurrentgemma_9b` | no | Gated repo (template not read); no tool support expected |
| `llama_3_8b` | no | Llama 3 (not 3.1) — template has no tool support |
| `falcon2_11b`, `falcon_7b`, `falcon_mamba_7b` | no | Base or older instruct models; no tool template |

## Not applicable

`deepseek_v4_flash_colibri`, `glm_5_2_colibri`, `inkling_colibri`,
`kimi_k3_colibri`, `olmoe_colibri` run in the external Colibri engine, which the
Code tab doesn't list.

## Hardware

The test machine has a 12 GB GPU. At Q4, models up to roughly 9 GB load fully on
the GPU (`qwen3_14b` 8.8 GB, `ministral_3_14b` 8.2 GB, `gemma_4_12b` 7.1 GB).
`gpt_oss_20b` (12.1 GB) and everything 16 GB and up (the 26B–34B models) will
spill to the CPU or not load — "should work" above does not mean "fits".

## Not covered

- **Server-side models.** The Python backend's `/v1/chat/completions` uses the
  same templates through `transformers`, so the verdicts above should carry over,
  but that path has never run against a real model (no torch installed here).
- **Quantisation.** Everything tested was Q4_K_M.
- **Real agent tasks.** Emitting a call is the minimum. Whether a model can plan
  a multi-step edit is a separate question these probes don't answer.
