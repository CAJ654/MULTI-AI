# Multi-AI
## Run using

```powershell
.\scripts\run-windows.ps1
```

equivalent to:

```powershell
cd app
flutter run -d windows
```

OR

(If using norton must first go to security -> network -> and disable smart firewall)

Or run the emulator + app in one go (boots Pixel_9, waits for it to come online, then `flutter run`s onto it):

```powershell
.\scripts\run-app.ps1
```

That's equivalent to, in order:

```powershell
# 1. start the emulator (takes ~60s to boot)
flutter emulators --launch Pixel_9

# 2. once it shows as a device, run
cd app
flutter run -d emulator-5554
```

## Restart backend

```powershell
.\scripts\restart-backend.ps1
```

That finds and kills whatever holds port 8000, then restarts the compiled backend's entry point — equivalent to, in order:

1. Find the process ID using port 8000:
Get-NetTCPConnection -LocalPort 8000 | Select-Object OwningProcess
That prints a number (the PID).

2. Stop it (replace <PID> with that number):
Stop-Process -Id <PID> -Force

3. Restart it (the backend is compiled — run the entry point, not the .pyx):
cd "c:/Users/cajga/Documents/GitHub/MULTI-AI/Multi-AI" && python -c "from multi_ai.server import run; run()"

multi-ai-server
(equivalently: `python -c "from multi_ai.server import run; run()"`. If you changed any .pyx, rebuild first — see Python Backend below.)

A hybrid Python/Dart edge computing platform for managing and running multiple AI models locally, with a Flutter mobile/desktop frontend.

## TODO: Extend on-device (GGUF/llama.cpp) model support

Mobile can't run the `transformers`/`torch`/`bitsandbytes` server backend (no CUDA, no mobile builds of those libs) — the on-device path is GGUF weights run through `llamadart`/llama.cpp, already proven with the built-in Qwen2.5 0.5B (`app/lib/on_device_engine.dart`). The `_GGUF_SOURCE` → `"gguf"` JSON field → `ModelInfo.gguf` routing in `chat_screen.dart` is already generic (any model with a `gguf` field auto-routes through `OnDeviceEngine`, no Dart changes needed) — only one model (`gptOSS.pyx`) currently uses it.

- [x] Add on-device sibling model files (declare `_GGUF_SOURCE` only, mirror `Multi-AI/multi_ai/models/gptOSS.pyx`'s shape) for verified-available GGUF quantizations, alongside their existing `_REPO_ID` file rather than replacing it (same pattern as the existing `llama3_2.pyx`/`llama_3_2_3b.pyx` duplication):
  - [x] `llama_3_2_1b_on_device.pyx` — `unsloth/Llama-3.2-1B-Instruct-GGUF`
  - [x] `llama_3_2_3b_on_device.pyx` — `unsloth/Llama-3.2-3B-Instruct-GGUF`
  - [x] `gemma_3_4b_on_device.pyx` — `unsloth/gemma-3-4b-it-GGUF`
  - [x] `deepseek_r1_distill_1_5b_on_device.pyx` — `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF`
  - [x] `falcon3_on_device.pyx` — `tiiuae/Falcon3-3B-Instruct-GGUF`
  - [x] `ministral_3_3b_on_device.pyx` — `mistralai/Ministral-3-3B-Instruct-2512-GGUF`
  - (all use the `Q4_K_M` quant, confirmed against each repo's file listing; note Falcon3's file is lowercase `q4_k_m`)
- [ ] Android: add `<uses-permission android:name="android.permission.INTERNET"/>` to `app/android/app/src/main/AndroidManifest.xml` (currently missing — needed for on-device GGUF downloads to work on a real device)
- [ ] iOS: verify `Info.plist`/ATS on first real device build (huggingface.co is standard HTTPS, likely needs no changes)
- [ ] Download progress UI: `llamadart` already exposes an `onProgress`/`ModelDownloadProgress.fraction` callback on `loadModelSource` (confirmed in the installed `llamadart-0.8.11` source) and already resumes partial downloads itself — just thread the callback from `OnDeviceEngine._ensureLoaded`/`generate` (`app/lib/on_device_engine.dart`) up into `chat_screen.dart`'s thinking-row UI (`_buildThinkingRow`, currently a static "Thinking…" string)
- [ ] Verify: `pytest -q` (roster/import tests) → `flutter run -d windows` (desktop llamadart run, no phone needed) → real Android build (the one thing desktop testing can't catch is the missing `INTERNET` permission)

## File Architecture

```
MULTI-AI/
├── pyproject.toml                 # build-system: setuptools + Cython (so `pip install -e .` works)
├── setup.py                       # Cython build — compiles every .pyx under Multi-AI/ to a .pyd/.so
├── Multi-AI/
│   ├── multi_ai/                  # the importable Python package
│   │   ├── server.pyx             # stdlib HTTP backend: /api/models, /api/chat, /api/hello
│   │   ├── server.c               #   └─ Cython-generated C (build input, regenerated)
│   │   ├── server.cp314-win_amd64.pyd  #   └─ compiled module — what actually runs (git-ignored)
│   │   ├── __init__.pyx           # package init (compiled like everything else)
│   │   └── models/                # 47 model entries — one file per model (server + on-device siblings)
│   │       ├── llama_3_2_3b.pyx           # server model: declares _REPO_ID (HF checkpoint)
│   │       ├── llama_3_2_3b_on_device.pyx # on-device sibling: declares _GGUF_SOURCE
│   │       └── …                          # falcon, gemma, mistral, qwen, deepseek, …
│   └── tests/                     # test_imports / test_model_roster / test_model_downloads (.pyx)
└── app/                           # Flutter frontend (lib/chat_screen.dart, on_device_engine.dart, …)
```

### What the `.pyx`, `.c`, and `.pyd`/`.so` files are

The Python backend is written in **Cython** and **must be compiled before it runs** — the runtime imports the compiled extension modules, never the `.pyx` source. You see three file types for what is conceptually one module because they're three stages of the same pipeline:

| File | Stage | Role |
|---|---|---|
| **`.pyx`** | source | What you edit. The source of truth — one file per model, plus `server.pyx`. Tracked in git. |
| **`.c`** | generated | Cython transpiles each `.pyx` into equivalent C (`cythonize()` in [setup.py](setup.py)). A build input, regenerated from the `.pyx` — never edited by hand. |
| **`.pyd`** (Windows) / **`.so`** (Linux/macOS) | compiled | A C compiler turns the `.c` into a native **CPython extension module** — the thing that's actually imported and run. The suffix (`.cp314-win_amd64.pyd`) is the ABI tag — CPython 3.14, win-amd64 — so the interpreter only loads a binary built for its exact version and platform. **Git-ignored**: platform/version-specific, so each machine rebuilds it. |

**You must compile before running.** `pip install -e . --no-deps` (from the repo root) invokes [setup.py](setup.py), which Cython-compiles every `.pyx` into a `.pyd`/`.so` next to its source and registers the package. This needs **Cython + a C compiler** (MSVC Build Tools on Windows, `gcc`/`clang` elsewhere). `--no-deps` builds the extensions without pulling the heavy chat-time deps (torch/transformers), which are lazy-imported only when you actually chat. Re-run it after adding or editing any `.pyx` — until you do, that model imports as `(broken)`.

### How models are loaded (compiled imports, no source fallback)

Because the `.pyx` are compiled to real extension modules, the code that consumes them imports them normally:

- [server.pyx](Multi-AI/multi_ai/server.pyx)'s `_load_model_module()` does `importlib.import_module("multi_ai.models.<id>")`. It enumerates *which* models exist by scanning the directory for `*.pyx` (the source-of-truth list), then imports the compiled module for each. A `.pyx` with no matching `.pyd` raises `ImportError` and surfaces as an `(broken)`/unavailable entry — a "you forgot to recompile" signal, **not** a silent fallback to source.
- The test suite ([tests/](Multi-AI/tests/)) imports the same compiled modules. The test *files* themselves stay plain-Python `.pyx` loaded by pytest's [conftest.py](Multi-AI/tests/conftest.py) — the harness is source-loaded even though the runtime it drives is compiled-only.

### How a model file is structured

Each `models/*.pyx` is a tiny, declarative stub — a `get_info()` dict plus one module-level constant that says *how* it runs:

- **`_REPO_ID`** → a Hugging Face checkpoint the **server** loads via `transformers` (4-bit quantized to fit laptop VRAM).
- **`_GGUF_SOURCE`** → an `hf://…/*.gguf` URI the **Flutter app** runs **on-device** through `llamadart`/llama.cpp; the server never touches it. Surfaces as the `gguf` field on `/api/models`, which auto-routes through `OnDeviceEngine` in the app.

A model can have both — a `_REPO_ID` file for the server and a parallel `_on_device.pyx` sibling declaring `_GGUF_SOURCE` — which is exactly the on-device roster added above.

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

The backend is compiled — build it once (and after any `.pyx` change) from the repo root:

```bash
pip install -e . --no-deps
```

This Cython-compiles every `.pyx` under `Multi-AI/` into a native `.pyd`/`.so` next to its source and registers the package. It needs **Cython + a C compiler** (MSVC Build Tools on Windows; `gcc`/`clang` elsewhere). `--no-deps` skips the heavy chat-time deps (torch/transformers), which are imported lazily only when you chat — install them separately when you need them.

Run a model directly (imports the compiled module and prints its metadata):

```bash
python -c "import multi_ai.models.qwen3_8b as m; print(m.get_info())"
```

Run the API server (serves `/api/hello`, `/api/models`, and `/api/chat` on `http://localhost:8000`, which the Flutter app's chat screen calls):

```bash
multi-ai-server
```

> The `multi-ai-server` console script is created by the editable install. If its directory isn't on your PATH, use `python -c "from multi_ai.server import run; run()"` instead. A compiled extension module can't be launched as a script the way `python server.pyx` could, which is why there's a dedicated entry point.

Every model under `models/` points at a real Hugging Face checkpoint: 24 declare a `_REPO_ID` and the server loads/generates with `transformers`, while 23 declare a `_GGUF_SOURCE` and run on-device in the app via llama.cpp instead. Most GGUF entries are `_on_device` siblings of a server model; `gptOSS` is the exception, GGUF-only, because the transformers path won't fit in RAM. Selecting a model in the chat UI downloads its weights on first use (seconds for `gpt2`, much longer for multi-billion-parameter models) and keeps it cached in memory afterward.

Gated model families (Llama, Gemma) need a Hugging Face access token: run `huggingface-cli login`, or set `HF_TOKEN` in the environment, before chatting with one.

### Image and audio input (multimodal models)

Five models accept more than text, declared per-model via `_INPUT_MODALITIES` and surfaced as `input_modalities` on `/api/models`:

| Model | Accepts |
|---|---|
| `gemma3n` / `gemma_3n` (Gemma 3n E2B) | text, image, **audio** |
| `gemma_3_4b` (Gemma 3 4B) | text, image |
| `ministral_3_3b` / `_8b` / `_14b` | text, image |

The app gates its input buttons on that field: a **+** button left of the text box appears only for image-capable models, and a **microphone** button between the text box and Send appears only for audio-capable ones. A text-only model shows neither. Switching to a model that can't take what's staged drops those attachments and says so, rather than silently discarding them at send time.

Attachments ride along on `POST /api/chat` as base64 (`attachments: [{kind, mime_type, name, data}]`, 32MB each), get written to temp files, and go through the model's `AutoProcessor` chat template — the text-only tokenizer path is untouched. A model that doesn't declare a modality rejects it server-side, so the gate holds even if a client ignores it.

**On-device image input works too, via a second GGUF.** llama.cpp encodes images through a separate *multimodal projector* file (`libmtmd`), so a vision GGUF needs both the text weights and an `mmproj-*.gguf`. A model file declares that companion with `_GGUF_MMPROJ_SOURCE`, surfaced as `mmproj` on `/api/models`; `OnDeviceEngine` downloads it and calls `loadMultimodalProjector()` before generating. Four on-device entries have one:

| On-device entry | Projector |
|---|---|
| `gemma_3_4b_on_device` | `mmproj-F16.gguf` |
| `ministral_3_8b_on_device` / `_14b_on_device` | `mmproj-F16.gguf` |
| `ministral_3_3b_on_device` | `…-BF16-mmproj.gguf` (mistralai's repo ships only BF16) |

A GGUF entry earns a non-text modality **only** by declaring a projector — text weights alone load and chat but silently can't see. `gemma3n_on_device` is the one multimodal checkpoint with no projector published anywhere (llama.cpp doesn't implement Gemma 3n's vision/audio towers), so it stays text-only; use the server-backed `gemma3n` for its image and audio input.

Downloading a vision model fetches both files, and neither the Models tab nor the chat picker counts it as downloaded until both are cached — otherwise the + button would appear against a model that can't actually see. Deleting removes both.

**On-device audio is not available at all.** The four projector-equipped models are vision-only; the one audio-capable checkpoint (Gemma 3n) has no llama.cpp projector. Audio input means the server.

Multimodal generation needs extra chat-time deps beyond `torch`/`transformers`:

```bash
pip install pillow torchvision          # image input
pip install librosa soundfile           # audio input (Gemma 3n)
pip install timm                        # Gemma 3n specifically — its vision tower is a timm model
```

When a model fails to load, the reply names the specific missing dependency. (It used to append "gated repos need HF_TOKEN" to *every* load failure, which sent you hunting for an auth problem when the real cause was a missing package.)

`torchvision` must match your torch build — on CUDA 12.8, `pip install torchvision --index-url https://download.pytorch.org/whl/cu128`. Without it, image sends fail with "PixtralProcessor requires the Torchvision library".

> **The Flutter app now needs Windows Developer Mode.** The image picker (`file_picker`) and recorder (`record`) are plugins, and Flutter's Windows desktop build symlinks plugin sources — so `flutter run -d windows` fails with "Building with plugins requires symlink support" until you run `start ms-settings:developers` and turn Developer Mode on (one-time). This is a change from before: the app previously avoided all plugins for exactly this reason (see the note in `chat_store.dart` about not using `path_provider`). Android/iOS builds are unaffected.

> If every HTTPS request fails with `CERTIFICATE_VERIFY_FAILED`, something on your machine (antivirus or a network proxy) is intercepting TLS with a non-standard root certificate. `pip install pip-system-certs` makes Python trust the Windows certificate store instead of its bundled list, which usually fixes it.

Run tests (from the `Multi-AI/` directory, where the pytest config and `conftest.py` live — and after building, since the tests import the compiled modules):

```bash
pip install pytest
cd Multi-AI
pytest -q
```

- `tests/test_imports.pyx` — every `models/*.pyx` file compiles, imports, and declares `get_info()` plus a `_REPO_ID`/`_GGUF_SOURCE`.
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
- [ ] `gptOSS` (GPT-OSS 20B) — rerouted to run **on-device** via llama.cpp GGUF (native MXFP4, 12.11GB download on first chat); via transformers it dequantizes to ~40GB, more than this machine's RAM. Duplicate `GPTOSSS20b.pyx` removed (2026-07-18: its orphaned `__pycache__/GPTOSSS20b.cpython-314.pyc` was still tracked in git; untracked and deleted). Server side verified 2026-07-18: roster lists it as available with `gguf` set and no `_REPO_ID`, `/api/chat` correctly defers to the app, and `ggml-org/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf` resolves and is **ungated** (no `HF_TOKEN` needed). Still unrun: actual on-device generation through llamadart.

Removed (2026-07-17: all models previously marked "unavailable" were deleted from the project):

- [x] `deepseek_v3_2_speciale_7b` — deleted per request (the real model is a huge MoE, not 7B)
- [x] `falcon_40b` — deleted: ~22GB at 4-bit > 12GB VRAM. Its ~78GB weight cache at `~/.cache/huggingface/hub` was deleted too (2026-07-17)
- [x] `mixtral_8x7b` — deleted: ~47B MoE, same problem
- [x] `pixtral_12b` / `kimi_instant_edge` — deleted (multimodal-only / no public small checkpoint)

- [x] Fix `.gitignore` — excludes `venv/`, `__pycache__/`, `*.egg-info/`, `build/`, and the compiled `.pyd`/`.so` binaries (platform/version-specific, rebuilt per machine). The generated `.c` stays tracked as a build input.
- [x] Flesh out real model implementations end-to-end — all 25 remaining models call real Hugging Face checkpoints via `transformers` (see `_REPO_ID` in each model file) or run on-device via a `_GGUF_SOURCE`; unavailable stubs were deleted
- [x] Wire up the API layer so the Flutter frontend (`app/lib/chat_screen.dart`) talks to a real backend handler — see `multi_ai.server`
- [x] `models/__init__.pyx` cleaned up — it re-exports nothing; `multi_ai.server` imports each compiled model module by name (`importlib.import_module`), and `tests/test_imports.pyx` validates all of them the same way
- [ ] Add a download-progress / "downloading model…" indicator in the chat UI — right now a first-time chat request just blocks until the weights finish downloading
- [x] Compile the `.pyx` sources for real (Cython + MSVC/`gcc`) — the backend is now compiled-only: `pip install -e . --no-deps` builds every `.pyx` to a `.pyd`/`.so` and the runtime imports the compiled modules (no plain-Python-script path)
- [x] Persist chat history to disk (`%APPDATA%\multi_ai\chat_sessions.json` on Windows) — chats survive restarts until deleted via right-click → Delete on a sidebar chat (see `app/lib/chat_store.dart`)
- [x] First on-device inference proof of concept (Qwen2.5 0.5B via `llamadart`/llama.cpp, no server needed) — see `app/lib/on_device_engine.dart`
- [x] Configurable "thinking" status text (word/phrase groups inspired by other AI products' loaders — Classic, Dev Tools, Quirky, and a Transparency Log group), with a settings dialog to enable/disable each group or individual phrases — see `app/lib/thinking_words.dart`, `thinking_settings.dart`, `thinking_settings_dialog.dart`, `thinking_indicator.dart`, and the gear icon in the chat top bar
  - The Transparency Log phrases are templated (`{query}`/`{model}` placeholders filled via `fillThinkingTemplate()`) so they narrate the actual in-flight request — e.g. `Searching for "what's the capital of..."…` / `Assembling Qwen2.5 0.5B's response…` — instead of generic text; the settings dialog shows a generic filled-in preview since it has no live request to reference
  - Regression-tested: `late` fields whose initializer reads themselves (as the original phrase-picker did, to avoid repeating a phrase) don't throw — they silently corrupt the value — so `app/test/chat_screen_test.dart`'s "sending a message shows the thinking row without crashing" test drives an actual send to catch that class of bug
- [x] Expand on-device support to more/larger models with GGUF builds (mirroring the server's `_REPO_ID` roster) — 22 of the 24 server models now have an on-device `_GGUF_SOURCE` sibling (Q4_K_M). Skipped only where no clean llama.cpp GGUF exists: `gemma_3n`/`llama3_2` are duplicate stems already covered by `gemma3n`/`llama_3_2_3b`; every other model has a sibling.
- [ ] Add a model-download size/progress indicator before committing a phone's storage — the roster now includes 8–14B on-device entries (Ministral 3 14B, Mistral Nemo 12B, Falcon2 11B) that are desktop-viable but too big for most phones, so surfacing size/device-fit before download matters more now
- [ ] Decide if/how `multi_ai.server`'s model roster and the on-device roster should be unified (e.g. one config listing both a `_REPO_ID` for the server and a GGUF source for on-device, per model)

## TODO: Core + add-on architecture
 The Chat tab, the llama.cpp on-device path, and the model catalog's descriptive metadata all
exist; **none of the Core infrastructure the add-ons are supposed to sit on
does**. Ordering below follows the spec's own sequential action items — steps 3
and 7 are the real unblockers, and the spec warns that retrofitting the plugin
contract after an add-on is built is the expensive path.

### Partially complete

- [ ] **Model catalog audit** (spec #4/#8) — param counts and sizes are resolved for all 47 entries via `get_info()`, including the previously ambiguous ones (`gemma1`→2B, `gemma2`→2B, `falcon3`→3B, `gptOSS`→20B, `llama3`/`llama3_1`→8B). Still missing as *structured* fields: `quant_level` (only implicit in the GGUF filename/prose) and `architecture_type` (dense vs. MoE vs. Mamba-hybrid — matters because `falcon_mamba_7b`/`falcon_h1` have different compute characteristics than a standard transformer).
- [ ] **Naming convention fix** (spec action item #2) — filenames still encode no size: `gemma1.pyx`, `gemma2.pyx`, `falcon3.pyx`, `llama3.pyx`. Rename to `gemma2_2b`-style so the variant can't go ambiguous again as the catalog grows.
- [ ] **Resource management** — `OnDeviceEngine._ensureLoaded` (`app/lib/on_device_engine.dart`) enforces one resident model and evicts on switch, which covers "which model is loaded". There is no RAM/VRAM *budget* — just single-tenancy.
- [ ] **Desktop vs. mobile catalog split** — models split by `_REPO_ID` (server, 4-bit GPU) vs. `_GGUF_SOURCE` (in-app), but that's a *where it runs* distinction, not the hardware-aware gating layer the spec describes. No `platform_support` field, no per-device labelling.
- [ ] **Orchestration and Code tabs** — sidebar shells only, marked "under construction" (`_SidebarTab` in `app/lib/chat_screen.dart`). No behavior behind either.

### Not started

- [ ] **Plugin/add-on interface contract** (spec #3) — the two new tabs are hardcoded enum cases, not plugins. Needs the mandatory lifecycle (`onInstall`, `onEnable`, `onDisable`, `registerUI`) plus optional declared capabilities (`requires: ["model_pool", "memory"]`). Must land *before* either add-on is fleshed out.
- [ ] **`model_registry` SQLite table** (spec #5) — no SQLite anywhere in the project; model metadata lives in per-file `.pyx` dicts. Missing every gating column: `quant_level`, `architecture_type`, `min_ram_mb`, `recommended_ram_mb`, `platform_support`, `role_tags`. Since `get_info()` already holds most of the descriptive fields, populating it is largely a migration script.
- [ ] **Memory layer** (spec #2) — the four-table model (`raw_items`, `wiki_entries`, `outputs`, `memory_index`) doesn't exist. `app/lib/chat_store.dart` is a flat JSON file of chat sessions, not a queryable memory tier.
- [ ] **Device × model compatibility estimator** (spec #6) — no device-spec probing, no predicted tokens/sec, no thermal/battery estimate. Ship the heuristic v1 but keep the input/output contract swappable for a trained regression later.
- [ ] **Recommended / Possible but not ideal / Not Supported tiering** (spec #7) — every model appears in the dropdown regardless of device; a phone can currently select the 20B `gptOSS`. Overlaps with the existing "surface size/device-fit before download" TODO above — same problem, and the tiering layer is the real fix for it.
- [ ] **Skill manifest format** (spec #1) — no `skill.json`/JSON Schema, no paired `skill.md` front matter, no MD↔JSON sync, no drag-and-drop editor.
- [ ] **Agentic OS add-on** (all four levels) — no skill registry, no review/retry loop engine, no memory browser, no task view, no tab.
- [ ] **Orchestration routing logic** — model choice is a manual dropdown. Routing must consume the Core tiering so it never picks a model flagged Not Supported on the device.
- [ ] **Code add-on** — dedicated coding-assistant mode. Lightest lift of the three; introduces no new shared infrastructure.

### Catalog cleanup surfaced while auditing

- [ ] Duplicate/inconsistent stems: both `gemma3n` and `gemma_3n` exist, as do `llama3_2` alongside `llama_3_2_1b`/`llama_3_2_3b`. Some are stale duplicates (already noted as skipped for on-device siblings above). Resolve as part of the rename pass rather than after.
- [ ] `gemma3n`'s `params` is `"E2B"` (effective-params notation) — won't parse into `model_registry.param_count INTEGER`, and it's the architecture case (MatFormer) the estimator most needs a real number for.

### Unresolved: two competing architecture plans

The spec above and the **Architecture Plan** section below describe different
backends for overlapping features — SQLite + llama.cpp + local skill registry
vs. PocketBase + R2 + MLC LLM. The spec's Orchestration add-on and the plan's
"Model Council" are the same feature described twice. Pick one before building
Core, or explicitly scope PocketBase as sync-only on top of the local SQLite
registry.

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
