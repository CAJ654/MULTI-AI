# Multi-AI
Run using
cd app
flutter run -d windows

A hybrid Python/Dart edge computing platform for managing and running multiple AI models locally, with a Flutter mobile/desktop frontend.

## Structure

```
MULTI-AI/
├── Multi-AI/multi_ai/   # Python package — Cython model stubs and utilities
│   └── models/          # 31 model entries (falcon, gemma, llama, mistral, qwen, etc.)
├── app/                 # Flutter frontend
└── tests/               # Import validation tests
```

## Frontend (Flutter)

Install dependencies:

```bash
cd app
flutter pub get
```

Run:

```bash
flutter run
```

Run tests:

```bash
flutter test
```

The chat model dropdown always includes one **on-device** entry (currently Qwen2.5 0.5B, via [`llamadart`](https://pub.dev/packages/llamadart)/llama.cpp) that runs locally with no server or network calls after its first download — works even if the Python backend below isn't running. Every other entry in the dropdown comes from the backend and runs there. See `app/lib/on_device_engine.dart`.

## Python Backend

Install the package (editable):

```bash
pip install -e .
```

Run a model directly:

```bash
python -m multi_ai.models.qwen3_8b
```

Run the API server (serves `/api/hello`, `/api/models`, and `/api/chat` on `http://localhost:8000`, which the Flutter app's chat screen calls):

```bash
python Multi-AI/multi_ai/server.pyx
```

> Compiling the `.pyx` sources into native extensions requires Cython and a C compiler (e.g. MSVC Build Tools on Windows, or `gcc`) — but none of that is required to run the server. Everything here is plain-Python source, so `python <file>.pyx` runs it directly via the interpreter without a compile step.

Most models under `models/` point at a real Hugging Face checkpoint (see each file's `_REPO_ID`) and the server loads/generates with `transformers`. Selecting a model in the chat UI downloads its weights on first use (seconds for `gpt2`, much longer for multi-billion-parameter models) and keeps it cached in memory afterward. A few models aren't wired up (see `_UNSUPPORTED_REASON` in `deepseek_v3_2_speciale_7b.pyx`, `kimi_instant_edge.pyx`, `pixtral_12b.pyx`) because no safely-small/text-only checkpoint exists for them.

Gated model families (Llama, Gemma) need a Hugging Face access token: run `huggingface-cli login`, or set `HF_TOKEN` in the environment, before chatting with one.

> If every HTTPS request fails with `CERTIFICATE_VERIFY_FAILED`, something on your machine (antivirus or a network proxy) is intercepting TLS with a non-standard root certificate. `pip install pip-system-certs` makes Python trust the Windows certificate store instead of its bundled list, which usually fixes it.

Run tests:

```bash
pip install pytest
pytest -q
```

## TODO

### Model status after the 2026-06-30 fix round

Root causes found for the manual-test failures: (1) the server fed raw text
instead of applying chat templates, so instruct models "continued" the prompt
— that was the "hallucinating"; (2) loaded models were never evicted, so
switching models stacked them in the 12GB GPU until it choked; (3) official
Gemma/Llama repos are gated; (4) Ministral 3 ships FP8 weights that need
Triton kernels which fail on Windows; (5) 20B+ models simply don't fit.

Verified working (each answered a test question correctly):

- [x] Qwen2.5 0.5B (on-device) — user-confirmed
- [x] `deepseek_r1_distill_1_5b` — fixed by chat template + `<think>` stripping (19s)
- [x] `falcon_h1` — fixed by chat template (6s)
- [x] `falcon3` — fixed by load fixes (10s)
- [x] `falcon2_11b` — fixed: a server bug was masking its real load error (47s)
- [x] `falcon_mamba_7b` — fixed; base model, replies truncated at invented turns (43s)
- [x] `ministral_3_3b` — fixed by swapping to the bf16 `unsloth` mirror (official FP8 weights need Triton kernels that don't work on Windows)
- [x] `llama_3_2_1b` — fixed by swapping to ungated `unsloth` mirror (4s)
- [x] `qwen3_8b` — regression-checked (17s)
- [x] `gpt2` — responds, but it's a 124M base model from 2019: rambling is inherent, now labeled "(base, no chat tuning)"

Fix applied, not yet run (weights download on first use):

- [ ] `gemma1/2/3/3n/_3_4b/_3n` — swapped to ungated `unsloth` mirrors (same proven mechanism as Llama)
- [ ] `llama3` / `llama3_1` / `llama3_2` / `llama_3_2_3b` — ungated mirrors
- [ ] `ministral_3_8b` / `ministral_3_14b` — bf16 mirrors (3B variant verified)
- [ ] `falcon_7b` — swapped to `falcon-7b-instruct` (base variant couldn't chat)
- [ ] `gptOSS` (GPT-OSS 20B) — rerouted to run **on-device** via llama.cpp GGUF (native MXFP4, ~12.8GB download on first chat); via transformers it dequantizes to ~40GB, more than this machine's RAM. Duplicate `GPTOSSS20b.pyx` removed.

Removed or intentionally unavailable:

- [x] `deepseek_v3_2_speciale_7b` — deleted per request (the real model is a huge MoE, not 7B)
- [x] `falcon_40b` — marked unavailable: ~22GB at 4-bit > 12GB VRAM. Its ~78GB weight cache at `~/.cache/huggingface/hub/models--tiiuae--falcon-40b` can be deleted to reclaim disk
- [x] `mixtral_8x7b` — marked unavailable: ~47B MoE, same problem
- [x] `pixtral_12b` / `kimi_instant_edge` — unavailable with reasons (multimodal-only / no public small checkpoint); kimi's string-literal syntax error fixed

- [ ] Fix `.gitignore` — exclude `venv/`, `__pycache__/`, compiled `.so` binaries, and `.c` build artifacts
- [x] Flesh out real model implementations end-to-end — 27 of 31 models now call real Hugging Face checkpoints via `transformers` (see `_REPO_ID` in each model file); 3 remain stubs for documented reasons (`_UNSUPPORTED_REASON`)
- [x] Wire up the API layer so the Flutter frontend (`app/lib/chat_screen.dart`) talks to a real backend handler — see `multi_ai.server`
- [ ] `models/__init__.pyx` still doesn't import the current model set correctly (it's bypassed — `multi_ai.server` loads model files directly by path instead of through the package import system)
- [ ] Add a download-progress / "downloading model…" indicator in the chat UI — right now a first-time chat request just blocks until the weights finish downloading
- [ ] Compile the `.pyx` sources for real (Cython + a C compiler) instead of running them as plain Python scripts
- [x] Persist chat history to disk (`%APPDATA%\multi_ai\chat_sessions.json` on Windows) — chats survive restarts until deleted via right-click → Delete on a sidebar chat (see `app/lib/chat_store.dart`)
- [x] First on-device inference proof of concept (Qwen2.5 0.5B via `llamadart`/llama.cpp, no server needed) — see `app/lib/on_device_engine.dart`
- [ ] Expand on-device support to more/larger models with GGUF builds (mirroring the server's `_REPO_ID` roster), and add a model-download size/progress indicator before committing a phone's storage
- [ ] Decide if/how `multi_ai.server`'s model roster and the on-device roster should be unified (e.g. one config listing both a `_REPO_ID` for the server and a GGUF source for on-device, per model)

---

## Architecture Plan

In this setup, PocketBase becomes the Control Plane, handling user authentication, model metadata, and workflow synchronization.

### Tech Stack

| Category | Technology | Role |
|---|---|---|
| Mobile Core | Flutter | Cross-platform UI and native hardware bridges |
| Edge Backend | PocketBase | Auth, Model Registry, and Workflow Sync |
| Local AI Engine | MLC LLM | Direct NPU/GPU access for model execution |
| Storage (Logic) | PocketBase Collections | Metadata, user profiles, and workflow JSONs |
| Storage (Large Files) | S3-Compatible (Cloudflare R2) | Hosting 5GB+ model files |

### How PocketBase Manages Models

Model files (`.gguf`, `.mlc`) are too large for SQLite. The solution is S3 linking:

- In the PocketBase Admin UI (Settings > File storage), enable S3 and enter Cloudflare R2 credentials.
- Create a `models` collection with fields: `name`, `version`, `requirements` (JSON), `model_file` (File).
- Uploaded models are stored in R2; PocketBase keeps only the metadata. The app fetches the list and downloads files via a direct URL.

> **Important:** Don't use PocketBase's proxied file URLs for large models — it will exhaust server RAM. Use S3 presigned URLs so the client downloads directly from the storage bucket.

### On-Demand Model Downloads

All 37 models are stored in R2 and only downloaded to the device when the user explicitly chooses to use one. This keeps the local footprint minimal while still giving access to the full model library.

The model browser UI should surface the `requirements` JSON (RAM, disk space) from the PocketBase `models` collection **before** the user downloads, so they can confirm their device can handle it.

Download experience goals:
- **Background download queue** — downloads continue while the user does other things in the app
- **Progress tracking** — show download progress per model
- **Resumable downloads** — use HTTP range requests against R2 presigned URLs so an interrupted download can continue rather than restart
- **Delete locally, keep access** — users can remove a model from device storage to free space; it remains in the library and can be re-downloaded anytime

### Workflow Customizer

- Create a `workflows` PocketBase collection.
- When a user saves a workflow in the Flutter flow-graph editor, the JSON is persisted to this collection.
- PocketBase's built-in Realtime Subscriptions sync changes across devices instantly — no custom sync code needed.

### Model Council (AI Orchestration)

Users can select multiple models, designate one as the **lead**, ask a question, and receive a synthesized answer. The models deliberate before the lead responds.

**How it works:**

1. User selects N models and picks one as the lead.
2. All non-lead models receive the question and respond independently (or in sequence — see deliberation modes below).
3. The lead model receives all responses alongside the original question and acts as a synthesizer/judge — identifying agreements, contradictions, and gaps before giving a final consolidated answer.

**Deliberation modes (to be decided):**

| Mode | Description | Trade-off |
|---|---|---|
| Parallel | All models answer independently; lead synthesizes | Fast, less interactive |
| Sequential | Each model sees the previous answer before responding | Richer debate, slower |
| Multi-round | Several back-and-forth rounds before final answer | Most thorough, highest latency |

The lead model should receive a specific system prompt for its synthesizer role, distinct from its normal inference prompt.

### Why PocketBase over Dify

- **Minimal footprint**: One binary vs. a full Docker Compose stack (Postgres, Redis, etc.) — runs on a Raspberry Pi or a $4/month VPS.
- **Flutter SDK**: Fetching model data is a one-liner: `pb.collection('models').getFullList()`
- **Built-in auth**: Email/password and OAuth (Google, Apple) out of the box.
