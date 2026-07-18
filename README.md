TODO: Add These for thinking as options inspired by other ais
Accomplishing, Actioning, Actualizing, Architecting, Baking, Beaming, Beboppin', Befuddling, Billowing, Blanching, Bloviating, Boogieing, Boondoggling, Booping, Bootstrapping, Brewing, Burrowing, Calculating, Canoodling, Caramelizing, Cascading, Catapulting, Cerebrating, Channeling, Channelling, Choreographing, Churning, Clauding, Coalescing, Cogitating, Combobulating, Composing, Computing, Concocting, Considering, Contemplating, Cooking, Crafting, Creating, Crunching, Crystallizing, Cultivating, Deciphering, Deliberating, Determining, Dilly-dallying, Discombobulating, Doing, Doodling, Drizzling, Ebbing, Effecting, Elucidating, Embellishing, Enchanting, Envisioning, Evaporating, Fermenting, Fiddle-faddling, Finagling, Flambeing, Flibbertigibbeting, Flowing, Flummoxing, Fluttering, Forging, Forming, Frolicking, Frosting, Gallivanting, Galloping, Garnishing, Generating, Germinating, Gitifying, Grooving, Gusting, Harmonizing, Hashing, Hatching, Herding, Honking, Hullaballooing, Hyperspacing, Ideating, Imagining, Improvising, Incubating, Inferring, Infusing, Ionizing, Jitterbugging, Julienning, Kneading, Leavening, Levitating, Lollygagging, Manifesting, Marinating, Meandering, Metamorphosing, Misting, Moonwalking, Moseying, Mulling, Mustering, Musing, Nebulizing, Nesting, Newspapering, Noodling, Nucleating, Orbiting, Orchestrating, Osmosing, Perambulating, Percolating, Perusing, Philosophising, Photosynthesizing, Pollinating, Pondering, Pontificating, Pouncing, Precipitating, Prestidigitating, Processing, Proofing, Propagating, Puttering, Puzzling, Quantumizing, Razzle-dazzling, Razzmatazzing, Recombobulating, Reticulating, Roosting, Ruminating, Sauteing, Scampering, Schlepping, Scurrying, Seasoning, Shenaniganing, Shimmying, Simmering, Skedaddling, Sketching, Slithering, Smooshing, Sock-hopping, Spelunking, Spinning, Sprouting, Stewing, Sublimating, Swirling, Swooping, Symbioting, Synthesizing, Tempering, Thinking, Thundering, Tinkering, Tomfoolering, Topsy-turvying, Transfiguring, Transmuting, Twisting, Undulating, Unfurling, Unravelling, Vibing, Waddling, Wandering, Warping, Whatchamacalliting, Whirlpooling, Whirring, Whisking, Wibbling, Working, Wrangling, Zesting, Zigzagging

show a raw, natural language summary of their actual inner monologue (e.g., "Let's double-check the physics constraints," "Re-evaluating step 3 for errors")

The Action LogRather than trying to be funny or whimsical, Perplexity AI uses a high-utility, step-by-step transparency log. While it processes your prompt, you will see it dynamically display its actual cognitive steps in real time:"Searching for..." (lists the exact search terms it is firing into the web)"Reading..." (shows the URLs of the specific articles and domains it is scraping)"Synthesizing..." (indicates it is actively merging the information into a final answer)

Frontend dev tools
"Planning component layout...""Generating Tailwind styles...""Assembling React code...""Rendering preview..."

The Sims: Famous for its incredibly bizarre loading messages like "Reticulating splines," "Generating emotional turbulence," and "Cajoling llamas."Slack: Rotates through uplifting quotes, community tips, or custom witty greetings added by your workplace workspace admin while loading the application.Discord: Rotates through quirky, millennial-humor status text like "Rerouting power to warp drive," "Knitting sweaters," and "Watering the digital plants."

# Multi-AI
## Run using
cd app
flutter run -d windows

## Restart backend
1. Find the process ID using port 8000:
Get-NetTCPConnection -LocalPort 8000 | Select-Object OwningProcess
That prints a number (the PID).

2. Stop it (replace <PID> with that number):
Stop-Process -Id <PID> -Force

3. Resart It:
python Multi-AI/multi_ai/server.pyx

A hybrid Python/Dart edge computing platform for managing and running multiple AI models locally, with a Flutter mobile/desktop frontend.

## TODO: Extend on-device (GGUF/llama.cpp) model support

Mobile can't run the `transformers`/`torch`/`bitsandbytes` server backend (no CUDA, no mobile builds of those libs) — the on-device path is GGUF weights run through `llamadart`/llama.cpp, already proven with the built-in Qwen2.5 0.5B (`app/lib/on_device_engine.dart`). The `_GGUF_SOURCE` → `"gguf"` JSON field → `ModelInfo.gguf` routing in `chat_screen.dart` is already generic (any model with a `gguf` field auto-routes through `OnDeviceEngine`, no Dart changes needed) — only one model (`gptOSS.pyx`) currently uses it.

- [ ] Add on-device sibling model files (declare `_GGUF_SOURCE` only, mirror `Multi-AI/multi_ai/models/gptOSS.pyx`'s shape) for verified-available GGUF quantizations, alongside their existing `_REPO_ID` file rather than replacing it (same pattern as the existing `llama3_2.pyx`/`llama_3_2_3b.pyx` duplication):
  - [ ] `llama_3_2_1b_on_device.pyx` — `unsloth/Llama-3.2-1B-Instruct-GGUF`
  - [ ] `llama_3_2_3b_on_device.pyx` — `unsloth/Llama-3.2-3B-Instruct-GGUF`
  - [ ] `gemma_3_4b_on_device.pyx` — `unsloth/gemma-3-4b-it-GGUF`
  - [ ] `deepseek_r1_distill_1_5b_on_device.pyx` — `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF`
  - [ ] `falcon3_on_device.pyx` — `tiiuae/Falcon3-3B-Instruct-GGUF`
  - [ ] `ministral_3_3b_on_device.pyx` — `mistralai/Ministral-3-3B-Instruct-2512-GGUF`
  - (confirm exact quant filenames against each repo's file listing before committing the `hf://` URI)
- [ ] Android: add `<uses-permission android:name="android.permission.INTERNET"/>` to `app/android/app/src/main/AndroidManifest.xml` (currently missing — needed for on-device GGUF downloads to work on a real device)
- [ ] iOS: verify `Info.plist`/ATS on first real device build (huggingface.co is standard HTTPS, likely needs no changes)
- [ ] Download progress UI: `llamadart` already exposes an `onProgress`/`ModelDownloadProgress.fraction` callback on `loadModelSource` (confirmed in the installed `llamadart-0.8.11` source) and already resumes partial downloads itself — just thread the callback from `OnDeviceEngine._ensureLoaded`/`generate` (`app/lib/on_device_engine.dart`) up into `chat_screen.dart`'s thinking-row UI (`_buildThinkingRow`, currently a static "Thinking…" string)
- [ ] Verify: `pytest -q` (roster/import tests) → `flutter run -d windows` (desktop llamadart run, no phone needed) → real Android build (the one thing desktop testing can't catch is the missing `INTERNET` permission)

## Structure

```
MULTI-AI/
├── Multi-AI/multi_ai/   # Python package — Cython model stubs and utilities
│   └── models/          # 25 model entries (falcon, gemma, llama, mistral, qwen, etc.)
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
flutter run -d windows
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

Every model under `models/` points at a real Hugging Face checkpoint (see each file's `_REPO_ID`) and the server loads/generates with `transformers` — or, for `gptOSS`, declares a `_GGUF_SOURCE` and runs on-device in the app. Selecting a model in the chat UI downloads its weights on first use (seconds for `gpt2`, much longer for multi-billion-parameter models) and keeps it cached in memory afterward.

Gated model families (Llama, Gemma) need a Hugging Face access token: run `huggingface-cli login`, or set `HF_TOKEN` in the environment, before chatting with one.

> If every HTTPS request fails with `CERTIFICATE_VERIFY_FAILED`, something on your machine (antivirus or a network proxy) is intercepting TLS with a non-standard root certificate. `pip install pip-system-certs` makes Python trust the Windows certificate store instead of its bundled list, which usually fixes it.

Run tests:

```bash
pip install pytest
pytest -q
```

- `tests/test_imports.pyx` — every `models/*.pyx` file loads and declares `get_info()` plus a `_REPO_ID`/`_GGUF_SOURCE`.
- `tests/test_model_roster.pyx` — the model list matches `models/*.pyx` both internally and through the live `GET /api/models` endpoint (what the Flutter dropdown actually calls).
- `tests/test_model_downloads.pyx` — every declared `_REPO_ID`/`_GGUF_SOURCE` resolves on the Hugging Face Hub (metadata-only checks, no weights downloaded). Needs network; skips per-model on unreachable-Hub errors but fails on a genuinely broken/renamed source.

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

2026-07-17: "only the on-device Qwen works" root-caused — gpt2 generated past
its 1024-token position-embedding table (`max_new_tokens=1024` regardless of
context size), firing a CUDA device-side assert that corrupts the process's
GPU state and makes **every** server model fail until restart. The server now
clamps generation to each model's `max_position_embeddings` and flags
CUDA-poisoned state in error replies. Verified: gpt2 → falcon3 →
deepseek_r1_distill_1_5b all answer correctly in one server run.

Fix applied, not yet run (weights download on first use):

- [ ] `gemma1/2/3/3n/_3_4b/_3n` — swapped to ungated `unsloth` mirrors (same proven mechanism as Llama)
- [ ] `llama3` / `llama3_1` / `llama3_2` / `llama_3_2_3b` — ungated mirrors
- [ ] `ministral_3_8b` / `ministral_3_14b` — bf16 mirrors (3B variant verified)
- [ ] `falcon_7b` — swapped to `falcon-7b-instruct` (base variant couldn't chat)
- [ ] `gptOSS` (GPT-OSS 20B) — rerouted to run **on-device** via llama.cpp GGUF (native MXFP4, ~12.8GB download on first chat); via transformers it dequantizes to ~40GB, more than this machine's RAM. Duplicate `GPTOSSS20b.pyx` removed.

Removed (2026-07-17: all models previously marked "unavailable" were deleted from the project):

- [x] `deepseek_v3_2_speciale_7b` — deleted per request (the real model is a huge MoE, not 7B)
- [x] `falcon_40b` — deleted: ~22GB at 4-bit > 12GB VRAM. Its ~78GB weight cache at `~/.cache/huggingface/hub` was deleted too (2026-07-17)
- [x] `mixtral_8x7b` — deleted: ~47B MoE, same problem
- [x] `pixtral_12b` / `kimi_instant_edge` — deleted (multimodal-only / no public small checkpoint)

- [ ] Fix `.gitignore` — exclude `venv/`, `__pycache__/`, compiled `.so` binaries, and `.c` build artifacts
- [x] Flesh out real model implementations end-to-end — all 25 remaining models call real Hugging Face checkpoints via `transformers` (see `_REPO_ID` in each model file) or run on-device via a `_GGUF_SOURCE`; unavailable stubs were deleted
- [x] Wire up the API layer so the Flutter frontend (`app/lib/chat_screen.dart`) talks to a real backend handler — see `multi_ai.server`
- [x] `models/__init__.pyx` cleaned up — it intentionally imports nothing now (uncompiled `.pyx` files can't be imported as submodules); `multi_ai.server` loads model files by path, and `tests/test_imports.pyx` validates all of them the same way
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

- **Minimal footprint**: One binary vs. a full Docker Compose stack (Postgres, Redis, etc.) — runs my already setup backend
- **Flutter SDK**: Fetching model data is a one-liner: `pb.collection('models').getFullList()`
- **Built-in auth**: Email/password and OAuth (Google, Apple) out of the box.
