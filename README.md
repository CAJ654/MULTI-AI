# Multi-AI

## The Goals & The Problems

MULTI-AI exists to make on-device inference a viable default, not just a
fallback — every model that runs locally is a query the shared cloud
infrastructure never has to serve. That's the one lever this project can
actually pull; here's the full picture of where AI's environmental cost
actually sits.

### Problem 1: Training — not addressed here

Training a frontier model is a genuinely massive one-time cost — GPT-4-scale
runs are estimated at nine figures and enough energy to power a city for
days, largely because of the GPU-parallel compute it demands
([MIT Technology Review, 2025](https://www.technologyreview.com/2025/05/20/1116327/ai-energy-usage-climate-footprint-big-tech/)).
This project doesn't touch that side yet — it's out of scope until it
expands beyond running existing models.

### Problem 2: Inference — the actual target

Training happens once; inference happens every time someone asks a question,
and it now accounts for roughly 80–90% of AI's total compute demand and
climbing, precisely because millions of users query the same few
data-center models
([MIT Technology Review, 2025](https://www.technologyreview.com/2025/05/20/1116327/ai-energy-usage-climate-footprint-big-tech/)).
Running the model on the device asking the question removes that query from
the shared-infrastructure tally entirely — the cost shifts to local battery
drain, a tradeoff the user controls directly instead of one absorbed by a
data center's grid draw.

### Problem 3: Hardware — reuse over extraction

Data-center-scale AI runs on lithium, cobalt, copper, and rare earths, and
the mining behind them carries a real human and environmental cost that
increasingly lands on communities with the least ability to push back
([Fortune, 2026](https://fortune.com/2026/04/29/where-do-critical-minerals-come-from-ai-boom-data-centers-africa-middle-east/);
[Roha, 2026](https://medium.com/@Jamesroha/the-new-strip-mines-how-ai-infrastructure-is-repeating-appalachias-extraction-history-e4ac29c1b88b)).
A phone or laptop that already exists needs none of that new extraction —
on-device inference reuses hardware the user already owns instead of adding to server-rack demand.

## Run using

```powershell
.\scripts\run-windows.ps1
```

equivalent to:

```powershell
# The app depends on velopack_flutter, whose native-assets build hook compiles a
# Rust crate — so the build needs rustup/cargo on PATH (see "Rust toolchain" below).
# run-windows.ps1 prepends this automatically; the bare commands need it explicitly.
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
cd app
flutter run -d windows
```

> **One-time: install the Rust toolchain.** The app depends on `velopack_flutter`
> (the in-app updater), a flutter_rust_bridge package whose native-assets build hook
> compiles a Rust crate as part of `flutter run/build windows`. Without rustup/cargo
> the build fails with `Building native assets failed` — the hook can't run
> `rustup show active-toolchain`. Install it once:
>
> ```powershell
> winget install --id Rustlang.Rustup -e --source winget
> ```
>
> rustup installs into `%USERPROFILE%\.cargo\bin` and adds it to your User PATH, but a
> terminal opened **before** the install keeps a stale PATH and still can't see it —
> `run-windows.ps1` prepends that directory so it works either way. To get it onto PATH
> for every new terminal, fully restart your shell (quit and reopen VS Code if you use
> its integrated terminal) or reboot once. `--source winget` skips the `msstore` source,
> which fails behind this machine's Norton TLS interception (`0x8a15005e`).

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

That finds and kills whatever holds port 8000, then restarts the compiled backend's entry point. It only restarts the process — it does **not** build. If you changed a `.pyx` since the last build, regenerate its C and recompile first:

```powershell
python scripts/regen_cython.py      # needs Cython==3.3.0
pip install -e . --no-deps
```

`.\scripts\restart-backend.ps1` is equivalent to, in order:

1. Find the process ID using port 8000:
Get-NetTCPConnection -LocalPort 8000 | Select-Object OwningProcess
That prints a number (the PID).

2. Stop it (replace <PID> with that number):
Stop-Process -Id <PID> -Force

3. Restart it (the backend is compiled — run the entry point, not the .pyx):
cd "c:/Users/cajga/Documents/GitHub/MULTI-AI/Multi-AI"
python -c "from multi_ai.server import run; run()"

multi-ai-server
(equivalently: `python -c "from multi_ai.server import run; run()"`)

A hybrid Python/Dart edge computing platform for managing and running multiple AI models locally, with a Flutter mobile/desktop frontend.

## Shipping a Windows release

Push a tag and [`.github/workflows/release.yml`](.github/workflows/release.yml) builds the installer and opens a **draft** release with it attached:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

Review the draft on GitHub, then publish. A manual run from the Actions tab builds the same installer as a workflow artifact without creating a release — use that to test pipeline changes.

### Why an installer rather than a bare .exe

`flutter build windows` does **not** produce a standalone executable. It produces `multi_ai.exe` plus `flutter_windows.dll`, the plugin DLLs (`file_picker`, `record`, and llamadart's `ggml-vulkan.dll`/`mtmd.dll`) and a `data/` directory. Ship the `.exe` alone and it won't launch. [`installer/multi-ai.iss`](installer/multi-ai.iss) wraps the whole tree into one `MultiAI-Setup-<version>.exe` — that single file is the release asset.

### Why the dependencies aren't in it

The chat-time stack is ~4.5 GB installed (torch alone is 4.12 GB — the `cu128` wheel carries the CUDA runtime inside `torch/lib`), and **a GitHub release asset is capped at 2 GB**. No compression closes that gap. So the split is:

| Ships in the installer (~200 MB) | Installed on first launch (~2.5 GB) |
|---|---|
| Flutter app + DLLs + `data/` | torch, transformers, accelerate, bitsandbytes |
| Embeddable CPython 3.14 (~11 MB) | pillow, torchvision, librosa, soundfile, timm |
| The Cython-compiled `multi_ai` package | pip-system-certs |
| `bootstrap.py`, `pip.pyz`, `requirements.txt` | (from PyPI + PyTorch's index, not hosted here) |

First launch shows a setup screen with pip's live output — a 10-minute install behind a bare spinner is indistinguishable from a hang. It's skippable: the on-device GGUF models need none of it, so a failed or declined install costs the server models rather than the app.

### Runtime layout

```
C:\Program Files\Multi-AI\          (read-only, admin to install)
  multi_ai.exe, *.dll, data\        the Flutter app
  backend\python\                   embeddable CPython 3.14
  backend\multi_ai\*.pyd            the compiled backend
  backend\bootstrap.py, pip.pyz, requirements.txt

%LOCALAPPDATA%\MultiAI\
  site-packages\                    torch et al. land here
  .provisioned                      the requirements.txt they satisfy
```

Dependencies install under `%LOCALAPPDATA%` deliberately: Program Files isn't user-writable, and a first launch that's already a long download shouldn't also need an admin prompt. The `.provisioned` marker holds the `requirements.txt` those packages were installed from, so an update that edits the list re-provisions instead of running against stale packages.

### Three traps worth knowing before editing any of this

- **The embeddable interpreter ignores `PYTHONPATH`.** Its `python._pth` replaces path setup wholesale, so the obvious fix — point `PYTHONPATH` at the dependency directory — silently does nothing and `import torch` fails with paths that look correct. [`installer/runtime/bootstrap.py`](installer/runtime/bootstrap.py) takes a `MULTI_AI_PATH` env var instead and builds `sys.path` after startup, where nothing is overriding it. The workflow does still un-comment `import site` in the `._pth`, because `pip.pyz` needs the `site` module.
- **pip is a zipapp, not an install.** The interpreter lives in Program Files and isn't writable at runtime, so there's nowhere for a real `pip install` to go. `pip.pyz` runs without being installed and writes to `--target`.
- **The `.pyd` ABI tag must match the bundled interpreter.** `server.cp314-win_amd64.pyd` loads only under CPython 3.14 on win-amd64. `PYTHON_VERSION` and `PYTHON_EMBED_VERSION` in the workflow have to stay on the same minor version; patch releases are ABI-compatible.

The installer is **unsigned**, so Windows SmartScreen warns that the publisher is unknown and users must click *More info* → *Run anyway*. Fixing that means an Authenticode certificate (~$100–400/yr from a CA); an EV certificate clears SmartScreen immediately, a standard one only after enough downloads build reputation.

### Backend lifecycle

The app owns the backend process in a packaged build: [`app/lib/backend_process.dart`](app/lib/backend_process.dart) spawns it, polls `/api/hello` until healthy, and kills it on exit. It first checks whether something already answers on port 8000 and adopts it if so — otherwise a developer's hand-started server, or an orphan from a previous crash, would collide with a fresh spawn and produce an "address in use" crash loop.

In development none of this engages: with no `backend/` directory next to the executable, `BackendRuntime.isBundled` is false, [`startup_gate.dart`](app/lib/startup_gate.dart) falls straight through to the chat screen, and you keep starting the server yourself as before.

## Shipping an Android release

Android ships as a signed APK attached to the same GitHub release as the Windows installer — deliberately **not** the Play Store. The Play Console path adds a $25 developer-account fee, a mandatory 14-day/12-tester closed test before any production release, a privacy-policy URL, and a Data Safety questionnaire, none of which this project needs for a sideloaded download. The tradeoff: no store listing, and no automatic updates — see "No in-app updater" below.

Pushing a tag builds and attaches both platforms to one release:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

[`.github/workflows/release.yml`](.github/workflows/release.yml) runs `build-windows` and `build-android` in parallel, then a `publish` job attaches both platforms' outputs to one draft release. Android needs none of the Windows job's backend-bundling steps — per the on-device-only scoping decision below, the APK is just the Flutter app.

### The release keystore

Android refuses to install an update over an existing app unless the new APK is signed with the *same* key, so unlike Windows (which ships unsigned and eats a SmartScreen warning) Android needs a real, stable signing identity from the first release onward.

The keystore was generated once, locally:

```powershell
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias multiai -storepass:file <password-file> -keypass:file <password-file> -dname "CN=Multi-AI, OU=CAJ654, O=Multi-AI, L=Unknown, ST=Unknown, C=US"
```

`app/android/upload-keystore.jks` and `app/android/key.properties` (storePassword/keyPassword/keyAlias/storeFile) are both gitignored — never commit them. [`app/android/app/build.gradle.kts`](app/android/app/build.gradle.kts) reads `key.properties` if present and signs with it; if it's absent (a fresh clone with no keystore set up), it falls back to debug signing so `flutter run`/`flutter build apk` still work locally without extra setup.

CI reconstructs the keystore from three repo secrets — **Settings → Secrets and variables → Actions** on GitHub:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("upload-keystore.jks"))` |
| `ANDROID_KEYSTORE_PASSWORD` | The store/key password (PKCS12 keystores require these to match) |
| `ANDROID_KEY_ALIAS` | `multiai` |

The `build-android` job decodes the first secret back into `upload-keystore.jks`, writes `key.properties` from the other two, builds, then verifies with `apksigner verify --print-certs` that the result is *not* signed with the debug key — a missing or wrong secret fails that check loudly instead of silently shipping a debug-signed APK nobody can update over later.

**If the keystore is ever lost**, there is no recovery — a new one means a new signing identity, and every existing install has to be uninstalled before it can take an "update" signed by the new key. Back up `upload-keystore.jks` and its password somewhere durable (a password manager, not just this machine) the same way you'd back up any other credential with no reset flow.

### No in-app updater

`velopack_flutter` (the Windows updater — see "Shipping a Windows release" above) explicitly no-ops its native build on Android (`hook/build.dart` returns early for `OS.android`/`OS.iOS`), and `initializeVelopack`/`UpdateService.checkNow()` are called unconditionally at startup on every platform but fail silently where there's no Velopack install to check against — so Android runs the same code path as everyone else without needing a platform guard, it just never finds an update. Getting a new version means downloading the new APK from the release page and installing it over the old one; Android accepts that as an upgrade (not a fresh install) as long as it's signed with the same key, so chat history and downloaded on-device models are preserved.

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

## Colibri: external-endpoint models on this edge server (5 MoE families)

[Colibri](https://github.com/JustVugg/colibri) runs a handful of large MoE
models on consumer hardware by streaming individual experts from disk instead
of residing the whole model in RAM. It is **not** a general model loader —
it's "one C file per model family," hand-written engines that hardcode each
family's tokenizer, attention mechanism, and MoE routing — so it only runs
the five families it explicitly implements, and can't be pointed at an
arbitrary checkpoint. (This is why it can't help with GPT-OSS or this
project's dense 10–14B models — see the TODO below.)

None of the five fit either existing model path (`_REPO_ID` →
transformers/torch, `_GGUF_SOURCE` → on-device llamadart): each needs a
separately-downloaded weight set (167GB–1.6TB, resolved to a real Hugging
Face repo per family — see `_COLIBRI_REPO_ID` below) and runs as its own
long-running process on this edge server (`coli serve --model <path> --port
8010`). Unlike the original design, **MULTI-AI now downloads those weights
and starts/stops that process itself** — the Models tab's usual
download/cache/delete UI works for these five the same as any `_REPO_ID`
model, and sending a chat message spawns `coli serve` automatically if it
isn't already running for that model, blocking the reply until it answers
`/health` or a clear error can be shown. Only one Colibri process runs at a
time (shared port 8010), so switching to a different Colibri model stops
whatever was running first. The one thing still manual: **the `coli` binary
itself** — install it once from
[Colibri's releases](https://github.com/JustVugg/colibri/releases) and put
it on PATH, the same one-time shape as this project's Rust-toolchain step.
Without it on PATH, a chat attempt returns a clear "install `coli`" message
rather than hanging.

| Model | Params (active) | Disk | RAM (min / comfortable) | Context | License | `_COLIBRI_REPO_ID` |
|---|---|---|---|---|---|---|
| GLM-5.2 | 744B (~40–55B) | ~372GB | 16GB / 24GB | 1M | Apache-2.0 engine / MIT weights | `jlnsrk/GLM-5.2-colibri-int4` |
| Inkling | 975B (~41B) | ~469GB | 64GB / 120GB | 1M | Apache 2.0 | `sabrewing-engine/Inkling-colibri-int4` |
| Kimi K3 | 2.8T (~104B) | ~1.6TB | 32GB / 32GB | ~1.05M | Kimi K3 License (custom) | `moonshotai/Kimi-K3` |
| DeepSeek V4 Flash | 284B (~13B) | ~167GB | 16GB / 22GB | 1M | MIT | `deepseek-ai/DeepSeek-V4-Flash-0731` |
| OLMoE | 7B (~1B) | ~4GB | 8GB / 8GB | 4096 | Apache 2.0 (+ Gemma ToU note) | `allenai/OLMoE-1B-7B-0924-Instruct` |

GLM-5.2 and Inkling need a one-time int4 conversion Colibri doesn't do
automatically, so their `_COLIBRI_REPO_ID` points at a pre-converted
community mirror rather than the base checkpoint. Kimi K3, DeepSeek V4
Flash, and OLMoE stream directly from their official repos — no conversion
needed. Downloading needs `huggingface_hub` installed
(`pip install huggingface_hub`) — deliberately **not** the full
torch/transformers chat-time stack, since Colibri needs neither.

(Inkling's 64GB floor is Colibri's own doc'd threshold — below it the process
dies mid-generation; a 25GB int4-dense-container fallback mode exists but is
disk-bound and impractically slow, so it isn't what's rated here.)

- [x] Five model files under `Multi-AI/multi_ai/models/` — one per family
      (`glm_5_2_colibri.pyx`, `inkling_colibri.pyx`, `kimi_k3_colibri.pyx`,
      `deepseek_v4_flash_colibri.pyx`, `olmoe_colibri.pyx`), each declaring
      `_EXTERNAL_ENDPOINT = "colibri"`, `_EXTERNAL_ENDPOINT_PORT = 8010`,
      `_EXTERNAL_MIN_RAM_GB`/`_EXTERNAL_RECOMMENDED_RAM_GB`, `_COLIBRI_REPO_ID`
      (the Hub source above), and a `get_info()` with the figures in the
      table above.
- [x] `server.pyx`: `_resolve_server_model` now recognizes `_COLIBRI_REPO_ID`
      alongside `_REPO_ID` (returning which *kind* it is), so the existing
      `GET/POST/DELETE /api/models/{id}/cache|download` routes work for
      Colibri models too — `_download_colibri_weights()` fetches the repo via
      `huggingface_hub.snapshot_download()` without loading it (unlike
      `_download_hf_weights`, which would try to load a 284B-2.8T checkpoint
      through `transformers`).
- [x] `server.pyx`: `_ensure_colibri_running(model_id, port)` — spawns
      `coli serve --model <path> --port 8010` (subprocess.Popen, output
      drained on a daemon thread so the pipe never blocks the child) and
      polls `GET /health` until it answers or a timeout/early-exit produces a
      clear error with the captured log tail. Called from `_chat_reply`
      before `_colibri_generate()` proxies the actual request. Requires
      weights already downloaded (`local_files_only=True` — chatting never
      triggers a 167GB-1.6TB download itself) and the `coli` binary on PATH;
      each missing piece gets its own specific error message.
- [x] `hardware.pyx`: `rate_external_model(min_ram_gb, recommended_ram_gb,
      disk_gb, specs)` — rates off local RAM against each family's own stated
      minimums (`rate_model`'s `bool(gguf)` discriminator couldn't grow a third
      case in place, so this is a sibling function, not a branch inside it).
      Always notes the disk requirement in the `reason` text regardless of the
      RAM verdict — for one of these models that one-time download is the real
      commitment.
- [x] Shared fixed port `8010` for all five (avoids colliding with MULTI-AI's
      own backend on 8000). All five default to the same port since realistically
      only one Colibri process runs at a time — each family needs its own
      hundreds-of-GB-to-terabyte weight set, so running two simultaneously isn't
      a realistic scenario; `_ensure_colibri_running` stops whichever family was
      running before starting a different one. A per-model
      `_EXTERNAL_ENDPOINT_PORT` override exists if that assumption ever needs
      to change.
- [x] Dart side — `api_client.dart`/`model_pool.dart`/`chat_screen.dart` route
      these through the normal `_api.sendChat()` path unchanged (no `gguf`
      field), as originally expected. What wasn't anticipated: `ModelInfo` had
      no way to tell a `_REPO_ID` model (server-managed weights) apart from an
      `_EXTERNAL_ENDPOINT` one — both lack `gguf`, and now some
      `_EXTERNAL_ENDPOINT` models (the Colibri five) also have server-managed
      weights while others hypothetically might not. Fixed by adding
      `has_server_weights` to `/api/models` (true for `_REPO_ID` or
      `_COLIBRI_REPO_ID`) and threading it through `ModelInfo.hasServerWeights`,
      `model_detail_screen.dart`'s `_isServerModel` gate (now shows the normal
      download/cache/delete section for Colibri models instead of a static
      "run this command yourself" block), and `model_pool.dart`'s
      `isDownloaded()` (now genuinely checks cache status for these instead of
      hardcoding `true`).
- [x] Verify: `pytest -q` passes, including the Hub-resolution checks for all
      five `_COLIBRI_REPO_ID` values.
- [ ] Verify against a real `coli` install: start the backend, download OLMoE
      (the ~4GB family, the only one realistic to actually pull) from the
      Models tab, send it a chat message with no `coli serve` running yet, and
      confirm the backend spawns it automatically and the reply round-trips —
      including a second chat to a *different* Colibri model correctly
      stopping the first process first.

Explicitly out of scope: auto-fetching the `coli` binary itself (still a
one-time manual PATH install — see above), any installer/packaging changes,
SSE streaming in MULTI-AI's own `/api/chat`, running multiple Colibri
families at once.

## TODO: A real speedup for GPT-OSS 20B and the dense 10–14B models

Colibri (above) can't be the answer for these — it only implements the five
MoE families it ships hand-written engines for, GPT-OSS is a different MoE
architecture Colibri doesn't support (not even on its roadmap), and the
dense models (`falcon2_11b`, `mistral_nemo_12b`, `ministral_3_14b`) have no
experts to stream in the first place. Their slowness is a separate,
still-open problem:

- `gptOSS` on-device: **0.1 tok/s**, 198s for one short reply once it spills
  onto the CPU (see the Wave 0 benchmarks above) — technically works, not
  practically usable.
- `falcon2_11b`, `mistral_nemo_12b`, `ministral_3_14b`: server-side (`_REPO_ID`)
  they're rated against VRAM after 4-bit quantization same as everything
  else, and on-device they're the partial-offload candidates Wave 4 hasn't
  run yet.

Possible directions, none investigated yet:

- [ ] A dedicated llama.cpp **server** process instead of running GGUF
      in-app via llamadart — decouples generation from the Flutter process
      and might expose batching/scheduling llamadart's embedded use doesn't.
- [ ] Better quantization for the CPU-spill cases (a smaller quant, or one
      more suited to CPU inference than Q4_K_M).
- [ ] Tuning `_gpuLayerLadder` (`app/lib/on_device_engine.dart`) — it was
      calibrated on Vulkan against this machine's 11.7GB VRAM; revisit once
      Wave 3/4 (the 7–14B on-device entries) actually run.
- [ ] Whether `_CPU_FALLBACK_LIMIT_GB` in `hardware.pyx` (currently 10.0GB,
      calibrated on the single `gptOSS` data point) should apply more
      granularly once more large-model benchmarks exist.

## File Architecture

```
MULTI-AI/
├── pyproject.toml                 # build-system: setuptools only — no Cython in the build path
├── setup.py                       # compiles every committed .c under Multi-AI/ to a .pyd/.so
├── backend_build.py               # shared .pyx/.c module discovery (setup.py + regen_cython.py)
├── scripts/regen_cython.py        # the one place Cython runs: regenerates the .c from the .pyx
├── Multi-AI/
│   ├── multi_ai/                  # the importable Python package
│   │   ├── server.pyx             # stdlib HTTP backend: /api/models, /api/chat, /api/hello, /api/device
│   │   ├── hardware.pyx           # GPU/RAM detection + per-model green/yellow/red fit ratings
│   │   ├── server.c               #   └─ Cython-generated C, committed — what setup.py compiles
│   │   ├── server.cp314-win_amd64.pyd  #   └─ compiled module — what actually runs (git-ignored)
│   │   ├── __init__.pyx           # package init (compiled like everything else)
│   │   └── models/                # 47 model entries — one file per model (server + on-device siblings)
│   │       ├── llama_3_2_3b.pyx           # server model: declares _REPO_ID (HF checkpoint)
│   │       ├── llama_3_2_3b_on_device.pyx # on-device sibling: declares _GGUF_SOURCE
│   │       └── …                          # falcon, gemma, mistral, qwen, deepseek, …
│   └── tests/                     # test_imports / test_model_roster / test_model_downloads (.pyx)
└── app/                           # Flutter frontend
    └── lib/
        ├── chat_screen.dart       # thin entry point: builds the pool + host, then AppShell
        ├── app_shell.dart         # sidebar, tab bar, top bar, banners — the frame add-ons draw in
        ├── model_pool.dart        # the `model_pool` capability: roster, downloads, generate()
        ├── on_device_engine.dart  # llama.cpp/llamadart, one resident model
        └── addons/                # one directory per tab — see "Add-on architecture"
            ├── addon.dart, addon_host.dart, registry.dart
            ├── chat/              # chat_controller.dart + chat_addon.dart
            ├── models/            # the roster browser
            ├── orchestration/     # the Model Council (controller + addon)
            └── placeholder_addon.dart   # the Code tab, for now
```

### What the `.pyx`, `.c`, and `.pyd`/`.so` files are

The Python backend is written in **Cython** and **must be compiled before it runs** — the runtime imports the compiled extension modules, never the `.pyx` source. You see three file types for what is conceptually one module because they're three stages of the same pipeline:

| File | Stage | Role |
|---|---|---|
| **`.pyx`** | source | What you edit. The source of truth — one file per model, plus `server.pyx`. Tracked in git. |
| **`.c`** | generated, **committed** | Cython's transpilation of the `.pyx`. Regenerated only by [`scripts/regen_cython.py`](scripts/regen_cython.py) (pinned Cython) — never edited by hand — and committed alongside the `.pyx`. This is what the build actually compiles, so Cython isn't needed to build. |
| **`.pyd`** (Windows) / **`.so`** (Linux/macOS) | compiled | A C compiler turns the `.c` into a native **CPython extension module** — the thing that's actually imported and run. The suffix (`.cp314-win_amd64.pyd`) is the ABI tag — CPython 3.14, win-amd64 — so the interpreter only loads a binary built for its exact version and platform. **Git-ignored**: platform/version-specific, so each machine rebuilds it. |

**You must compile before running.** `pip install -e . --no-deps` (from the repo root) invokes [setup.py](setup.py), which compiles every committed `.c` into a `.pyd`/`.so` next to its source and registers the package. This needs **a C compiler** (MSVC Build Tools on Windows, `gcc`/`clang` elsewhere) but **not Cython**. `--no-deps` builds the extensions without pulling the heavy chat-time deps (torch/transformers), which are lazy-imported only when you actually chat. Re-run it after adding or editing any `.pyx` — until you do, that model imports as `(broken)`.

**If you change a `.pyx`:** run `python scripts/regen_cython.py` (needs `Cython==3.3.0` — the pin is in that script) and commit the regenerated `.c` with it. CI ([backend-check.yml](.github/workflows/backend-check.yml)) regenerates the `.c` and fails if the committed copy doesn't match, and the release build repeats that check before packaging — a stale `.c` shipped broken once (v1.0.1) and this is what stops it recurring.

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

The backend is compiled — build it once (and after any `.pyx`/`.c` change) from the repo root:

```bash
pip install -e . --no-deps
```

This compiles every committed `.c` under `Multi-AI/` into a native `.pyd`/`.so` next to its source and registers the package. It needs **a C compiler** (MSVC Build Tools on Windows; `gcc`/`clang` elsewhere) but **not Cython** — the `.c` are checked in. `--no-deps` skips the heavy chat-time deps (torch/transformers), which are imported lazily only when you chat — install them separately when you need them.

If you edit a `.pyx`, regenerate its `.c` before rebuilding: `pip install "Cython==3.3.0" && python scripts/regen_cython.py`, then commit the `.c` alongside the `.pyx` (CI enforces they stay in sync).

Run a model directly (imports the compiled module and prints its metadata):

```bash
python -c "import multi_ai.models.qwen3_8b as m; print(m.get_info())"
```

Run the API server (serves `/api/hello`, `/api/models`, `/api/chat`, and `/api/device` on `http://localhost:8000`, which the Flutter app's chat screen calls):

```bash
multi-ai-server
```

> The `multi-ai-server` console script is created by the editable install. If its directory isn't on your PATH, use `python -c "from multi_ai.server import run; run()"` instead. A compiled extension module can't be launched as a script the way `python server.pyx` could, which is why there's a dedicated entry point.

Every model under `models/` points at a real Hugging Face checkpoint: 23 declare a `_REPO_ID` and the server loads/generates with `transformers`, while 22 declare a `_GGUF_SOURCE` and run on-device in the app via llama.cpp instead. Most GGUF entries are `_on_device` siblings of a server model; `gptOSS` is the exception, GGUF-only, because the transformers path won't fit in RAM. Selecting a model in the chat UI downloads its weights on first use (a minute or two for the 1–3B models, much longer for multi-billion-parameter ones) and keeps it cached in memory afterward.

Gated model families (Llama, Gemma) need a Hugging Face access token: run `huggingface-cli login`, or set `HF_TOKEN` in the environment, before chatting with one.

### Conversation history

Each `/api/chat` request carries the prior turns as `history: [{role, content}, …]`, and the on-device path passes the same turns to llamadart as a list of `LlamaChatMessage`s. Both then build a multi-turn prompt.

**This was broken until 2026-07-19** — every message was sent alone, so the model answered each one as if it were the first. The UI showed a thread, which made a stateless model look like it was hallucinating; the tell was a follow-up like "What is my name?" drawing a blank one turn after the name was given. It affected every model, not just weak ones.

Long chats are trimmed rather than allowed to overflow:

- The oldest turns are dropped first, so the newest exchange — the part the reply depends on — always survives.
- The budget reserves room for the new message *and* the reply, so history can't crowd out the answer it was meant to inform.
- Trimming never leaves an assistant turn first; a reply with no question above it reads as the model talking to itself.
- Capped at 4096 tokens (`_MAX_HISTORY_TOKENS`) regardless of the model's advertised window: the 256K-context models can't practically attend that far in this much VRAM. The on-device side approximates the same cap in characters (~4/token), since the tokenizer lives behind llama.cpp's FFI.

Error rows and "(response stopped)" placeholders are UI state and are excluded from what gets sent. Malformed history entries are dropped individually rather than failing the request.

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

Verified against real weights (2026-07-19): `ministral_3_3b` and `gemma3n` both read a generated test image correctly, and `gemma3n` processed a WAV without error. The audio check used a synthesized 440Hz tone rather than speech — that exercises decode → feature extraction → audio encoder end-to-end, but says nothing about transcription quality on real speech, which is still untested. On-device (mmproj) image input is also untested against real weights: the plumbing and gating have unit coverage, but no projector has actually been downloaded and run.

`torchvision` must match your torch build — on CUDA 12.8, `pip install torchvision --index-url https://download.pytorch.org/whl/cu128`. Without it, image sends fail with "PixtralProcessor requires the Torchvision library".

> **The Flutter app now needs Windows Developer Mode.** The image picker (`file_picker`) and recorder (`record`) are plugins, and Flutter's Windows desktop build symlinks plugin sources — so `flutter run -d windows` fails with "Building with plugins requires symlink support" until you run `start ms-settings:developers` and turn Developer Mode on (one-time). This is a change from before: the app previously avoided all plugins for exactly this reason. That reasoning is now fully moot — `path_provider` was added too once `file_picker`/`record` had already paid this cost (see the Android persistence fix above). Android/iOS builds are unaffected.

> **Partial downloads used to fail silently.** Weights are loaded with `local_files_only=True` first (fast, and it dodges hub rate limits), but a half-finished cache satisfies that: the config JSON lands before the vocabulary, so a tokenizer loads *without error* and then encodes every token to `<unk>`. The prompt became one junk token, generation produced noise, and the reply was an unexplained "(model returned an empty response)" — which then repeated for the rest of the server's life, because the broken tokenizer was cached in memory. The server now sanity-checks a freshly loaded tokenizer, re-fetches from the hub if it's degenerate, and says so plainly if it still is.

> If every HTTPS request fails with `CERTIFICATE_VERIFY_FAILED`, something on your machine (antivirus or a network proxy) is intercepting TLS with a non-standard root certificate. `pip install pip-system-certs` makes Python trust the Windows certificate store instead of its bundled list, which usually fixes it.

### Hardware fit ratings

The roster spans 0.5B to 20B, and the difference between "this runs great" and "this downloads 12GB and then OOMs" isn't visible from a parameter count. So the backend sizes up the machine and rates every model against it, and the app colours each one:

| Badge | Meaning |
|---|---|
| 🟢 **Optimal** | Fits with headroom — full GPU offload, room left for a long conversation |
| 🟡 **Possible** | Runs, but tight on VRAM or partly CPU-bound. Usable, not fast |
| 🔴 **Not recommended** | Doesn't fit, or only "fits" by running mostly on the CPU at unusable speed |
| ⚪ **Unknown** | No CUDA GPU or unreadable memory total — a missing measurement, not a verdict |

`multi_ai/hardware.pyx` does the sizing: RAM via stdlib (`GlobalMemoryStatusEx` on Windows, `sysconf` elsewhere) and VRAM via a **lazily imported** `torch` — listing models still works on a machine that never installed the heavy deps, it just rates everything "unknown". Results are surfaced as a `fit` object per model on `/api/models`, plus a `GET /api/device` endpoint the app uses to caption the Models tab with the hardware being judged against.

The two run paths get **different formulas**, because `size_gb` means different things for each:

- **`_REPO_ID` (server)** — `size_gb` is the fp16 checkpoint, but transformers loads it 4-bit, so the estimate is `size/4 × 1.15 + 1.2GB` workspace and compares against **VRAM only**. Rating a 7B on its 14.5GB fp16 size would wrongly condemn most of the roster.
- **`_GGUF_SOURCE` (on-device)** — `size_gb` is already the quantized file, so `size × 1.1 + 0.8GB`. Three regimes: fits VRAM with headroom (full offload), fits but tight (llama.cpp drops layers), or spills to CPU.

The CPU-spill cutoff is calibrated on the Wave 0 benchmarks above rather than guessed: `gptOSS` (12.11GB) technically *passes* on this machine — the GPU-layer ladder rescues it — at **0.1 tok/s**, 198s for one short reply, while `falcon2_11b_on_device` (6.85GB) full-offloads at a usable 4.3 tok/s. So a GGUF that overflows VRAM and exceeds ~10GB rates red, not yellow: **"it runs" and "you'd wait three minutes for a sentence" are different claims**, and only one of them should be green.

Colour is never the only signal — every badge carries its text label and a one-line explanation in this machine's actual numbers ("Needs about 5.4 GB of your 11.9 GB VRAM — comfortable fit"), so the verdict is auditable rather than a mystery traffic light.

> **Scope caveat.** Ratings describe the **backend machine**, including for on-device GGUF entries. That's correct when the app and server run on the same desktop (the current setup) but wrong once the app runs on a phone against a remote backend — a phone can't be judged by its server's GPU. Rating on-device entries against the *app's* hardware needs a device-side probe that doesn't exist yet.

Run tests (from the `Multi-AI/` directory, where the pytest config and `conftest.py` live — and after building, since the tests import the compiled modules):

```bash
pip install pytest
cd Multi-AI
pytest -q
```

- `tests/test_imports.pyx` — every `models/*.pyx` file compiles, imports, and declares `get_info()` plus a `_REPO_ID`/`_GGUF_SOURCE`.
- `tests/test_model_roster.pyx` — the model list matches `models/*.pyx` both internally and through the live `GET /api/models` endpoint (what the Flutter dropdown actually calls).
- `tests/test_hardware_fit.pyx` — the fit ratings behave: rated against *synthetic* specs (a 12GB card, a 4GB card, no GPU) so the result doesn't change with whichever machine runs the suite, plus a monotonicity property (a bigger model must never rate better than a smaller one) and a check that every listed model carries a rating.
- `tests/test_model_downloads.pyx` — every declared `_REPO_ID`/`_GGUF_SOURCE` resolves on the Hugging Face Hub (metadata-only checks, no weights downloaded). Needs network; skips per-model on unreachable-Hub errors but fails on a genuinely broken/renamed source.

## TODO

### AI Orchestration Portion
  - [x] Create the Orchestration Page — the Model Council, see "Orchestration" above
  - LangGraph was the original idea here; it's Python-only and lives on the wrong
    side of the app/backend split. The Dart-side alternatives (Genkit, Agenix,
    dart_agent_core) were evaluated and declined — the council needs fan-out, not
    an agent framework. Revisit a framework only if routing grows real agent loops.
  - [ ] Multi-round deliberation (parallel and sequential ship; multi-round doesn't)
  - [ ] Preset manifests — make the member set, lead, mode and lead prompt a
    downloadable JSON recipe (the add-on contract's preset follow-on)

### AI Coding Tool Portion
  - Look into models that are great at text output & coding
  - Create coding page (still the placeholder add-on)

### Android

**Scope: Android only (iOS is not a target), and on-device GGUF only — the
phone never talks to the Python backend.** That second decision removes a lot
of work (no runtime server-URL setting, no LAN entry in
`network_security_config.xml`, no cleartext HTTP, and the Models tab's
server download/delete calls and `/api/device` header can be compiled out) but
it creates one new problem, below.

Already done, contrary to what the on-device TODO above still says: the
`INTERNET` and `RECORD_AUDIO` permissions are declared in
`app/android/app/src/main/AndroidManifest.xml`, `network_security_config.xml`
exists, and `chat_screen.dart` already has a `LayoutBuilder`/`Drawer` phone
layout.

- [x] **Bundle the model roster as an asset** — the app had no local roster:
      `_GGUF_SOURCE` lives in `Multi-AI/multi_ai/models/*.pyx`, Cython-compiled
      and server-side, so with no reachable backend `ModelPool.refresh()` fell
      back to a single hardcoded Qwen2.5 0.5B plus a red "Backend unreachable"
      banner. Fixed: `app/tool/generate_on_device_roster.dart` (a new,
      standalone `dart run` script, duplicating rather than importing
      `verify_on_device.dart`'s private `_parseRoster` — that one only reads 4
      of the 9 fields `ModelInfo` needs) parses every `.pyx` declaring a
      module-level `_GGUF_SOURCE` (27 today) and writes
      `app/assets/on_device_roster.json` in the same shape `/api/models`
      already emits, so `ModelInfo.fromJson` reads it with zero new parsing
      code. `ModelPool.refresh()` branches on a real, OS-level Android check
      (see the `platform_check.dart` note below) to load the asset instead of
      calling `fetchModels()`. Re-run the generator after any `.pyx` change and
      before any Android build — nothing does it automatically yet.
- [x] **Fix persistence — it was silently broken on mobile.**
      `chat_store.dart` and `thinking_settings.dart` (a byte-for-byte
      duplicate) resolved their data directory from `Platform.environment`,
      empty on Android, falling through to an unwritable relative path with a
      `catch (_)` swallowing the failure into "no history". Fixed with
      `path_provider`'s `getApplicationSupportDirectory()` — the stale
      Developer-Mode-avoidance reasoning no longer applies (`file_picker`/`record`
      already pay that cost). `thinking_settings.dart`'s duplicate is gone;
      it now calls `chat_store.dart`'s shared `appDataFile`, which also means
      `addon_host.dart`'s `AddOnStateStore` inherited the fix for free.
      `ChatStore`/`ThinkingSettingsStore` are now interfaces
      (`FileChatStore`/`FileThinkingSettingsStore` are the real
      implementations) so `InMemoryChatStore`/`InMemoryThinkingSettingsStore`
      exist for tests, mirroring `InMemoryAddOnStateStore`.
      A second, previously-unflagged gap: the on-device model *cache* has
      three independent construction sites (`ModelPool`, `ModelDetailScreen`,
      and `OnDeviceEngine`'s own `LlamaEngine`), each defaulting to
      `DefaultModelDownloadManager()`'s OS-purgeable temp-directory fallback on
      Android. All three now share one durable directory
      (`androidModelCacheDirectory()` in `model_pool.dart`) via
      `DefaultModelDownloadManager.appPrivate(...)`, threaded into
      `OnDeviceEngine` through a new settable `downloadManager` field (it stays
      Flutter-plugin-free itself, so `verify_on_device.dart` still runs under
      plain `dart run` — only the already-Flutter-bound `ModelPool` does the
      `path_provider` resolution and hands down the finished manager).
      **Trap worth knowing:** `defaultTargetPlatform` — the obvious way to
      check "is this Android" — is overridden to `TargetPlatform.android` by
      the `flutter_test` binding on every host OS, which silently broke every
      existing widget test the first time this landed (confirmed by probing it
      directly under `flutter test`). `app/lib/platform_check.dart` provides
      `isAndroidHost` instead: a conditional-import shim (`dart:io`'s real
      `Platform.isAndroid` where available, `false` on web) that's accurate
      under test. Everything above keys off `isAndroidPlatform` in
      `model_pool.dart` (`!kIsWeb && isAndroidHost`), not `defaultTargetPlatform`.
- [ ] **Device-side fit ratings** — currently `fit` comes from the backend and
      is null with no server, so every badge vanishes on the platform that needs
      it most: the roster carries `gptOSS` at 12.11GB and several 7–14B entries,
      and a phone will happily start a download that can never load. Simpler than
      the server version — only the GGUF formula applies (`size × 1.1 + 0.8GB`),
      against total RAM rather than VRAM. Realistically only the ≤2–3GB Q4
      entries should be listed at all. Supersedes the scope caveat under
      "Hardware fit ratings".
- [ ] **Verify llamadart's `android-arm64` backend before tuning anything.**
      `_gpuLayerLadder` in `app/lib/on_device_engine.dart` was calibrated on
      *Vulkan* against 11.7GB of dedicated VRAM; its own comment concedes the
      free-VRAM question "would be wrong on the phone targets anyway". If the
      Android bundle is CPU-only, `gpuLayers` is moot and the ladder just burns
      three reload attempts before landing on `0`. llamadart's `hook/build.dart`
      does ship real `android-arm64`/`android-x64` bundles, so no companion
      package is needed (unlike the iOS SwiftPM path) — but which compute backend
      is in them is unchecked.
- [ ] **Foreground service for downloads** — Android kills a multi-GB fetch as
      soon as the app backgrounds. Pairs with the download-progress indicator
      already open above.
- [x] **Release signing** — see "Shipping an Android release" above. A real
      keystore now signs release builds (falling back to debug only when
      `key.properties` is absent, e.g. a fresh clone); CI reconstructs it from
      repo secrets and verifies the result isn't debug-signed before shipping.
      Distribution is a signed APK on GitHub releases, not the Play Store —
      see that section for why.
- [ ] **On-device image input is unverified on Android** — the `mtmd` symbol
      resolution problem root-caused under `dart run` (see the on-device
      verification notes) has never been checked against an Android bundle.

Suggested order: roster asset and `path_provider` first (both independent of
any device being present, and together they make the build testable at all),
then `flutter run` on the Pixel_9 emulator for the first honest signal, then
device-side fit, then the foreground-download service.

### Linux

Unlike Android, Linux is a **full-fat desktop target**: both run paths (the
Python/`transformers` server *and* on-device GGUF) are in scope, because a Linux
box has the same CUDA and RAM story as the Windows dev machine. Most of the
work is therefore packaging and scripting, not architecture — none of it has
been attempted or verified, but very little of it looks hard.

What already works by construction, and is worth not re-solving:

- `setup.py` is platform-agnostic — it walks for the committed `.c` (via
  `backend_build.py`) and compiles each as an `Extension`, so `pip install -e .
  --no-deps` should produce `.cpython-314-x86_64-linux-gnu.so` files under
  `gcc`/`clang` with no changes. The `.c` are OS-independent (the regen
  normalises paths), so `scripts/regen_cython.py` and the backend-check CI job
  run anywhere. (The `.pyd` naming throughout this README is Windows-specific
  prose, not a code assumption.)
- `hardware.pyx` already branches: `GlobalMemoryStatusEx` on `win32`, and
  `os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")` everywhere else.
  The VRAM path is `torch.cuda`, which is if anything better supported on Linux.
- `chat_store.dart` and `thinking_settings.dart` resolve `XDG_DATA_HOME` (then
  `$HOME/.local/share`). Linux is the one platform where their environment-
  variable approach genuinely works — contrast the Android entry above, where
  the same code silently writes nowhere.
- `app/linux/` scaffolding exists (`CMakeLists.txt`, `runner/`,
  `my_application.cc`) and `record_linux` is registered in
  `generated_plugin_registrant.cc`.
- **No Developer Mode / symlink problem.** That constraint is Windows-only, so
  the plugin-avoidance reasoning documented elsewhere in this README does not
  apply here.
- llamadart's `hook/build.dart` ships `linux-x64` and `linux-arm64` bundles, so
  the native-assets path resolves with no companion package.

- [ ] **Decide the packaging story — this is the real fork in the road.**
      `installer/multi-ai.iss` is Inno Setup, Windows-only, and the trick it
      wraps does not port: there is no Linux equivalent of embeddable CPython,
      and the `python._pth` / `pip.pyz --target` dance exists purely to work
      around Program Files being read-only. On Linux the honest options are a
      `venv` built at first launch, or an AppImage/Flatpak carrying its own
      interpreter. Cheapest credible v1 — and the one that matches the Android
      scoping decision — is **"Linux is a source install"**: document
      `pip install -e . --no-deps` plus `flutter build linux`, ship no installer,
      and revisit once someone actually wants a one-click Linux download.
- [ ] **Port or explicitly disable the bundled-backend supervisor.**
      `app/lib/backend_process.dart` is hardcoded Windows throughout: backslash
      path joins, `python\python.exe`, `%LOCALAPPDATA%`, and an `isBundled`
      gated on `Platform.isWindows`. The *safe* current behaviour is that
      `isBundled` is false on Linux, so `startup_gate.dart` falls straight
      through to the chat screen and you start `multi-ai-server` yourself —
      exactly the development experience. That is fine and needs no code today;
      it only becomes work if the packaging decision above says otherwise.
      Whichever way it goes, the file should say so rather than leaving the
      Windows-only gate looking accidental.
- [ ] **Build-time system dependencies** — Flutter Linux desktop needs `clang`,
      `cmake`, `ninja-build`, `pkg-config` and `libgtk-3-dev`; `record_linux`
      additionally wants ALSA/PulseAudio headers. Document them, since a missing
      one surfaces as a CMake error rather than anything mentioning Flutter.
- [ ] **Runtime system dependency: `xdg-desktop-portal`.** `file_picker` 11
      talks to `org.freedesktop.portal.FileChooser` over D-Bus (`dartPluginClass`,
      so nothing appears in `generated_plugins.cmake` — its absence there is
      correct, not a bug). A headless or minimal desktop with no portal backend
      installed gets no file dialog, which will read as "the + button is
      broken". Note this is a **change from `file_picker` 8.x**, which shelled
      out to `zenity`/`qarma`/`kdialog` — don't follow older guidance found
      online.
- [ ] **Verify llamadart's `linux-x64` compute backend.** Same unknown as the
      Android entry: the Windows bundle turned out to be Vulkan (see the Wave 0
      notes), and the hook's CUDA-detection helpers (`_windowsCudartPattern`,
      `_hasWindowsBackendModule`) are explicitly Windows-only, so which backend
      Linux gets is unread. This decides whether `_gpuLayerLadder` is doing
      anything useful there or just burning reload attempts.
- [ ] **Shell-script equivalents** — `scripts/` is three PowerShell files
      (`run-windows.ps1`, `run-app.ps1`, `restart-backend.ps1`). The
      port-8000-holder lookup in `restart-backend.ps1` needs `lsof`/`ss` instead
      of `Get-NetTCPConnection`.
- [ ] **CI** — `.github/workflows/release.yml` is a single Windows job. Add a
      Linux build (at minimum `pip install -e . --no-deps` + `pytest -q` +
      `flutter build linux`, which would also catch Windows-only regressions in
      the backend early), or state that Linux is deliberately source-only.

Suggested order: build it once by hand end-to-end (`pip install -e . --no-deps`
→ `pytest -q` → `flutter build linux` → chat with one server model and one
on-device model) and let that tell you which of the above are real. The
packaging decision can wait until that works; everything else is downstream
of it.

### Model status after the 2026-07-20 fix round

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
(`"hi"` → `"hi"`, `"What color is the sky"` → `"What color is the moon?"`) and otherwise rambled. Nothing to fix — it was mostly a source of output that looked like a bug. Both `gpt2.pyx` and `gpt2_on_device.pyx` deleted; `gptOSS` (GPT-OSS 20B) is unrelated and stays.
- [x] `gemma1` — ungated `unsloth` mirror works (8s)
- [x] `gemma3n` / `gemma_3n` — all three modalities confirmed (2026-07-19): text (14s), image (5s, correctly read a red circle), audio (3s). Needed `pip install timm` — its vision tower is a `TimmWrapperModel`, and without it the load failed with an error the server then mislabeled as a gating problem.
- [x] `gemma_3_4b` — text (13s) and image (4s, correctly read the same test circle). Its first run returned "(model returned an empty response)": the weights were chatted with before the download finished, so `local_files_only=True` loaded a vocabulary-less tokenizer that encoded the whole prompt to one `<unk>`. See the partial-download guard below.
- [x] `gemma2` / `gemma3` — ungated `unsloth` mirrors, same mechanism as the `gemma1`/`gemma3n`/`gemma_3_4b` set now verified above; these two just aren't downloaded yet
- [x] `gptOSS` (GPT-OSS 20B) — rerouted to run **on-device** via llama.cpp GGUF (native MXFP4, 12.11GB download on first chat); via transformers it
- [x] `falcon_7b` — swapped to `falcon-7b-instruct` (base variant couldn't chat)

2026-07-17: "only the on-device Qwen works" root-caused — gpt2 generated past
its 1024-token position-embedding table (`max_new_tokens=1024` regardless of
context size), firing a CUDA device-side assert that corrupts the process's
GPU state and makes **every** server model fail until restart. The server now
clamps generation to each model's `max_position_embeddings` and flags
CUDA-poisoned state in error replies. Verified: gpt2 → falcon3 →
deepseek_r1_distill_1_5b all answer correctly in one server run.

Fix applied, not yet run (weights download on first use):


- [ ] `llama3` / `llama3_1` / `llama3_2` / `llama_3_2_3b` — ungated mirrors
- [ ] `ministral_3_8b` / `ministral_3_14b` — bf16 mirrors (3B variant verified)
 dequantizes to ~40GB, more than this machine's RAM. Duplicate `GPTOSSS20b.pyx` removed (2026-07-18: its orphaned `__pycache__/GPTOSSS20b.cpython-314.pyc` was still tracked in git; untracked and deleted). Server side verified 2026-07-18: roster lists it as available with `gguf` set and no `_REPO_ID`, `/api/chat` correctly defers to the app, and `ggml-org/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf` resolves and is **ungated** (no `HF_TOKEN` needed). **On-device generation verified 2026-07-19** — first attempt failed with `Failed to create context`: llamadart defaults to `gpuLayers: 999`, so all layers went to the GPU, the 11.28GB of weights fit inside 11.66GB of free VRAM, and nothing was left for the KV cache or compute buffers. llama.cpp reports that as a context-creation failure *after* a successful model load, which reads like a corrupt download. Fixed with a GPU-offload backoff ladder in `OnDeviceEngine._ensureLoaded` (`app/lib/on_device_engine.dart`) — it retries with progressively fewer offloaded layers, and small models still succeed on the first (full-offload) attempt unchanged.

### On-device GGUF verification (2026-07-19 – 2026-07-20, in progress)

Separate from the list above, which is scoped to the server/`transformers` path
— an entry there means "answered correctly via the Python backend", which is a
different claim from "loads and generates through llamadart on-device".

Run headless, no GUI and no server, from `app/`:

```
dart run tool/verify_on_device.dart --preflight   # cache status, downloads nothing
dart run tool/verify_on_device.dart --wave 0      # cached models only
```

`tool/verify_on_device.dart` drives the real `OnDeviceEngine` — the same code
path the app uses, including the GPU-offload ladder and the mmproj projector —
rather than a reimplementation that could drift. It parses the roster out of
`Multi-AI/multi_ai/models/*.pyx` so there is one source of truth, and flushes
results to `tool/.verify_results.json` after every model so a native crash
costs one result rather than the run. `--report` reprints the table without
re-running anything.

This was possible only because llamadart uses Dart **native assets/build
hooks** rather than a Flutter plugin, so `dart run` resolves the DLLs from
`app/.dart_tool/lib`. (Never run `dart pub get` in `app/` — the SDK-sourced
Flutter dep won't resolve and a partial `.dart_tool/` rewrite destroys that
state. Use `flutter pub get`.)

**A `pass` means the model loaded and generated coherent, non-echoing text —
not that it answered correctly.** Several roster models are base models that
ramble or emit `<think>` blocks; gating on answer content would measure model
quality instead of whether the stack works. The keyword check is recorded but
non-gating.

**Wave 0 — 4 of 4 passed** (already-cached models, zero downloads):

| Model | GB | GPU layers | First token | Gen | tok/s | Verdict | Reply |
|---|---|---|---|---|---|---|---|
| `gptOSS` | 12.11 | **12** | 40.9s | 198.5s | **0.1** | pass | `<\|channel\|>analysis<\|message\|>The user asks…` |
| `falcon2_11b_on_device` | 6.85 | 999 | 10.8s | 11.5s | 4.3 | pass | The capital city of France is Paris. |
| `gemma4_e2b_on_device` | 3.11 | 999 | 7.2s | 7.9s | 25.1 | pass | The capital of France is Paris. |
| `gemma3n_on_device` | 3.03 | 999 | 7.3s | 8.3s | 2.9 | pass | The capital of France is Paris. |
| Qwen2.5 0.5B (built-in) | 0.49 | 999 | 5.8s | 6.3s | 6.3 | pass | Paris is the capital city of France. |

(`gemma4_e2b` and the pre-0.8.16 numbers aren't directly comparable — everything
above `gemma4_e2b` was measured on llamadart 0.8.11 and would likely be faster
re-run today. Only Gemma 4 has been measured on `b9982`.)

The **GPU layers** column is the practical output of the exercise — it records
which rung of the `_gpuLayerLadder` each model needed. Three findings:

- **`falcon2_11b` full-offloads at 999.** 6.85GB fits comfortably beside its own
  runtime allocations in ~11.7GB, at a usable 4.3 tok/s. Since every remaining
  7–9B entry is 4.4–5.2GB at Q4_K_M, they should all full-offload too — this one
  zero-download data point de-risks that whole wave.
- **`gptOSS` passes but is not practically usable.** The ladder rescues it from
  the `Failed to create context` crash by dropping to 12 layers, but that means
  most of a 20B MoE runs on CPU: **0.1 tok/s**, 40.9s to first token, 198.5s for
  one short reply. "Working" and "usable" are different claims and this is the
  gap between them. Anything that makes it faster costs context or quality
  (smaller `contextSize` to buy back offload room, or a smaller quant).
- **The backend is Vulkan, not CUDA.** llamadart's prebuilt Windows bundle
  drives the RTX 5070 Ti through `ggml-vulkan.dll`. The VRAM arithmetic is
  unchanged, but the ladder is backing off *Vulkan* offload, and its allocator
  behaves differently under pressure than CUDA's.

**`gptOSS` leaks its harmony format into the reply.** The raw output begins
`<|channel|>analysis<|message|>…` — the app has no parser for GPT-OSS's channel
scaffolding, so a user would see that reasoning-channel markup verbatim in the
chat bubble. The harness strips `<|…|>` before judging, which is why it still
scores a pass; the *display* path has no such stripping. Unfiled — needs either
a harmony parser or a channel filter in `chat_screen.dart`, alongside the
existing `<think>`-stripping the server does.

**Falcon 7B Instruct on-device fixed and verified (2026-07-20).** It was
prefixing every reply with a wall of `<|im_start|>calculate` / `<|im_start|>while
loop` junk, then — mid-investigation — echoing the question back, leaking a
trailing `<|im_end|>`, and returning empty after the first turn. All of it was
one cause: `maddes8cht/tiiuae-falcon-7b-instruct-gguf` ships **no
`tokenizer.chat_template`**, so llama.cpp falls back to ChatML. Falcon-7B-Instruct
predates ChatML and was trained on a bare `User:`/`Assistant:` transcript; fed
`<|im_start|>` it has no `<|im_end|>` token to stop on and degenerates into
repeating `<|im_start|>assistant` forever.

The trap is that **`ModelParams.chatTemplate` does not fix this** — it is
silently ineffective on the path the app uses. `LlamaEngine.create()` renders its
prompt Dart-side in `ChatTemplateRenderer`, which reads `tokenizer.chat_template`
straight out of the GGUF metadata and never consults the model params.
(`llama_cpp_service`'s `applyChatTemplate` *does* honour them, but `create()`
doesn't go through it.) Setting it looks correct, analyzes clean, and changes
nothing.

The fix is a `_quirksBySource` table in `app/lib/on_device_engine.dart`: a
quirked model bypasses chat templating entirely and takes llamadart's low-level
`engine.generate(rawPrompt)` with the transcript built in Dart. Non-quirked
models take the original `create()` path untouched; both feed one shared
`Stream<String>`, so buffering, `onToken`, and cancellation are common.

Two things worth carrying forward to the next model that misbehaves like this:

- **Declaring a stop sequence does not keep its text out of the reply.**
  llama.cpp's decode loop `yield`s each token's bytes downstream *before* testing
  them against the stop list, and never retracts — so the text that triggered the
  stop is always already in the buffer. `OnDeviceEngine._trimStopMarker` strips a
  trailing match; this is independent of the templating question and applies to
  any model given stop sequences.
- **Dump the rendered prompt before theorising.** Four rounds of plausible
  fixes were aimed at the wrong layer because the prompt was assumed rather than
  inspected; one throwaway script printing the prompt and the raw bytes settled
  it immediately. `engine.chatTemplate(messages)` returns the exact string.

Verified end-to-end through `OnDeviceEngine` (not a reimplementation), three
turns with real history: `The capital of France is Paris.` →
`&lt;header&gt;&lt;/header&gt;` → a coherent follow-up. No markup, no echo, no
empties. Answer *quality* is the ceiling of a 4-bit 2023-era 7B — turn 3
confabulated — but the prompting stack is correct. Note this is the on-device
path only; the server/`transformers` `falcon_7b` entry above is unaffected.

**Gemma 3n on-device is text-only, and now says so (2026-07-19).**
`gemma3n_on_device.pyx` advertised `"modality": "Text + Image + Audio"` while
having no `_GGUF_MMPROJ_SOURCE`, so the Models tab promised image and audio that
the attachment buttons correctly refused to offer — the file contradicted its own
`strengths` text. Corrected to `"Text"`. The model *is* multimodal and the
server-backed `gemma3n` entry still delivers all three modalities; it's llama.cpp
that can't:

- No projector exists in any repo. `unsloth/gemma-3n-E2B-it-GGUF` ships 24 text
  quants and no mmproj; `ggml-org/gemma-3n-E2B-it-GGUF` — llama.cpp's own org —
  ships two text GGUFs. `lmstudio-community` names theirs `…-text-GGUF`.
- Gemma 3n uses MobileNet-V5 vision and a USM audio tower rather than Gemma 3's
  SigLIP, and is **absent** from llama.cpp's supported multimodal list.

**Gemma 4 E2B/E4B added as the on-device multimodal path.** Both are in
llama.cpp's vision *and* mixed-modality lists and ship "omni" GGUFs where one
projector covers image and audio. GGUF-only, no `_REPO_ID` sibling (same shape as
`gptOSS`). `gemma4_e2b_on_device` text verified: full offload, **25.1 tok/s**.

**llamadart 0.8.11 → 0.8.16.** Lockfile-only bump (the existing `^0.8.11`
constraint already allowed it). Native runtime `b9829` → `b9982`. Text throughput
on Gemma 4 E2B went **2.5 → 25.1 tok/s, a 10x speedup**, from the release's
"improved llama.cpp batching defaults". 19/19 Dart tests and 66 pytest tests
still pass.

**On-device image/audio is blocked under `dart run` — root-caused, and probably
harness-only.** Both Gemma 4 probes fail with *"Multimodal support is unavailable
in this native runtime bundle (missing `mtmd_context_params_default`)"*. That
message is misleading; the chain is:

1. `mtmd.dll` is fine. A direct `DynamicLibrary.open` of it from `.dart_tool/lib`
   succeeds and resolves `mtmd_context_params_default`, `mtmd_init_from_file`,
   and `mtmd_support_audio`. It exports 97 `mtmd_*` symbols, including
   `mtmd_audio_preprocessor_gemma4a`.
2. `bindings.dart` is annotated `@ffi.DefaultAsset('package:llamadart/llamadart')`,
   so every binding resolves against **llamadart.dll** — which does not contain
   the `mtmd_*` symbols. The primary lookup therefore always fails and llamadart
   falls back to opening `mtmd.dll` itself.
3. That fallback searches only the bare filename plus `_backendModuleDirectory`.
   Under `dart run` the executable is `dart.exe` and the CWD is `app/`, so
   neither looks like a native bundle and the directory resolves to null —
   nothing finds `.dart_tool/lib`. Setting `LLAMADART_NATIVE_LIB_DIR` does not
   help.

**A `flutter run -d windows` build stages those DLLs next to the `.exe`, which
*should* satisfy the executable-directory branch — so multimodal may well work in
the real app. That is a hypothesis, not a result: it has not been tested, and
confirming it needs the GUI path this harness exists to avoid.** Until someone
checks, treat on-device image/audio as unverified for all four projector-bearing
entries (`gemma4_e2b`, `gemma4_e4b`, `gemma_3_4b`, and the Ministrals), not as
broken.

`OnDeviceEngine._buildMessage` previously dropped audio attachments silently —
it filtered to `AttachmentKind.image` only. Now fixed to emit
`LlamaAudioContent`, which was a prerequisite for any entry honestly declaring
`audio`.

Not yet run — waves 1-4, ~65GB of downloads (`--preflight` reports 5 of 25
cached):

- [ ] Wave 1 (~4GB, resumes existing `.part` files) — `gemma_3_4b` (also the
      first test of the mmproj/vision path), `deepseek_r1_distill_1_5b`, `gemma1`
- [ ] Wave 2 (~15GB, ≤4GB models) — includes `ministral_3_3b`, whose BF16
      projector comes from `mistralai`'s own repo rather than the `unsloth`
      mirror the other three use
- [ ] Wave 3 (~30GB, 7-9B) — expected to full-offload per the `falcon2_11b` result
- [ ] Wave 4 (~17GB, 12-14B) — `mistral_nemo_12b`, `ministral_3_14b`; the
      partial-offload candidates, expect `gptOSS`-like speeds

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
- [x] Surface **device fit** before download — every model card and detail page now carries a green/yellow/red badge saying whether this machine can run it, so an 8–14B entry can't quietly cost a multi-gigabyte download that ends in an OOM. See "Hardware fit ratings" above (`multi_ai/hardware.pyx`, `GET /api/device`, `app/lib/model_fit_badge.dart`)
- [ ] Add a model-download **progress** indicator to go with it — the size is now shown up front, but a first-time download still gives no feedback while it runs
- [ ] Decide if/how `multi_ai.server`'s model roster and the on-device roster should be unified (e.g. one config listing both a `_REPO_ID` for the server and a GGUF source for on-device, per model)

## TODO: Core + add-on architecture

The plugin contract (spec #3) and the `model_pool` capability under it now
exist — see "Add-on architecture" below. The rest of Core does not. Ordering
follows the spec's own sequential action items; #7 (tiering) is the remaining
unblocker.

### Add-on architecture (done)

Every tab is an `AddOn` registered at compile time in
[`app/lib/addons/registry.dart`](app/lib/addons/registry.dart) — Models, Chat,
Orchestration and Code all sit on the same contract, with no privileged
built-in. Adding a feature is one file plus one registry entry.

| Piece | Where |
|---|---|
| The contract — `AddOnManifest`, `AddOnSurface`, lifecycle, `HostCapability` | [`addons/addon.dart`](app/lib/addons/addon.dart) |
| The host — registry, lifecycle, enable/disable, capability gating | [`addons/addon_host.dart`](app/lib/addons/addon_host.dart) |
| The frame every add-on draws inside | [`app/lib/app_shell.dart`](app/lib/app_shell.dart) |
| The `model_pool` capability | [`app/lib/model_pool.dart`](app/lib/model_pool.dart) |

An add-on contributes three optional surfaces — a **sidebar panel**, a **main
pane**, and a **top-bar slot** — so selecting a tab now swaps the whole window,
not just the sidebar. It declares what it needs (`requires: [HostCapability.modelPool]`)
and the host hands over exactly that; reaching for an undeclared capability
throws and names the fix. An add-on whose capabilities this build can't supply
renders as a disabled tab with the reason, never a broken pane.

**`model_pool`** is the roster, its download state, and the single `generate()`
that decides between the two run paths (a `gguf` source goes to llama.cpp
in-process; everything else to the Python backend). That decision used to be
inline in the chat screen's send handler reading private state, which is why
nothing else could run a model. On-device calls are serialized behind a queue:
`OnDeviceEngine` keeps exactly one model resident and evicts on switch, so a
Model Council asking several GGUFs at once would otherwise thrash multi-gigabyte
loads against each other.

Two things worth knowing before extending this:

- **Add-ons cannot be installed after the app is.** Flutter ships as machine
  code with no interpreter, so there is no way to load a new `.dart` file at
  runtime. Add-ons are registered at compile time and have a *lifecycle* at
  runtime; new ones reach users through the Velopack updater. `onInstall`
  accordingly means first-run setup on this machine — it runs once, and again
  only when a release bumps that add-on's `schemaVersion`, like a migration.
  The genuinely downloadable half is data, not code: a JSON *preset* naming
  which models a Council uses and what the lead's prompt is. That's spec #1's
  manifest, still open below.
- **Nothing may await the filesystem on the startup path.** Real file IO never
  completes under `flutter_test`'s fake-async binding, so a host that awaited
  its state file before enabling add-ons hung every widget test forever (and
  would hold the first paint behind a disk round trip in production). The shell
  renders its chrome immediately and the pane catches up; tests inject
  `InMemoryAddOnStateStore` so they neither read nor write the developer's real
  `%APPDATA%`. Covered by [`app/test/addon_host_test.dart`](app/test/addon_host_test.dart).

Still open here: nothing calls `AddOnHost.setEnabled` yet — the persistence and
gating work, but there is no settings UI to turn a tab off.

### Orchestration: the Model Council (done)

The Orchestration tab is a real add-on now
([`app/lib/addons/orchestration/`](app/lib/addons/orchestration/)), not the
placeholder. Pick two or more **downloaded** models in the sidebar, crown one as
**lead**, ask a question: the non-lead members answer, and the lead reads every
answer and returns one consolidated reply.

Built directly on [`ModelPool.generate()`](app/lib/model_pool.dart), **no agent
framework**. The evaluated options (Genkit Dart, Agenix, dart_agent_core) all
assume an LLM provider client, so each would have needed a custom adapter for
this app's two local run paths before doing anything — and the council is
fan-out plus a synthesis prompt, not the tool-use / planning / delegation those
frameworks exist for. `dart_agent_core` is the one to revisit *if* a future Code
tab wants a real agent loop: it's the only local-first option and it takes a
custom LLM client.

Two **deliberation modes**, picked in the sidebar (the README previously left
these "to be decided"):

- **Parallel** — each member answers the raw question, seeing nobody else's.
- **Sequential** — each member answers in turn, seeing the answers already given.

Both **run members serially**, not concurrently — a deliberate call, not a
missing feature. On one GPU there's nothing to gain: the on-device engine keeps
one model resident and the Python backend evicts on model switch, so
"simultaneous" generations would just thrash the same hardware. "Parallel" is
the *semantic* distinction (independent answers), not a threading one.

Robustness the controller
([`orchestration_controller.dart`](app/lib/addons/orchestration/orchestration_controller.dart))
handles, all under test in
[`app/test/orchestration_controller_test.dart`](app/test/orchestration_controller_test.dart):
a member that fails to load doesn't sink the run (the lead synthesizes whoever
answered); if *everyone* fails, the run says so and never asks the lead to
synthesize nothing; Stop discards late-arriving answers via a run-generation
guard; deleting a selected model from the Models tab drops it from the council,
and deselecting the lead promotes another member.

Not done: the synthesizer prompt is a sensible built-in, not yet the preset's
`leadPrompt` field — that's the downloadable-manifest follow-on. Multi-round
deliberation (the spec's third mode) is also still open; parallel and sequential
ship.

### Partially complete

- [ ] **Model catalog audit** (spec #4/#8) — param counts and sizes are resolved for all 47 entries via `get_info()`, including the previously ambiguous ones (`gemma1`→2B, `gemma2`→2B, `falcon3`→3B, `gptOSS`→20B, `llama3`/`llama3_1`→8B). Still missing as *structured* fields: `quant_level` (only implicit in the GGUF filename/prose) and `architecture_type` (dense vs. MoE vs. Mamba-hybrid — matters because `falcon_mamba_7b`/`falcon_h1` have different compute characteristics than a standard transformer).
- [ ] **Naming convention fix** (spec action item #2) — filenames still encode no size: `gemma1.pyx`, `gemma2.pyx`, `falcon3.pyx`, `llama3.pyx`. Rename to `gemma2_2b`-style so the variant can't go ambiguous again as the catalog grows.
- [ ] **Resource management** — `OnDeviceEngine._ensureLoaded` (`app/lib/on_device_engine.dart`) enforces one resident model and evicts on switch, which covers "which model is loaded". There is no RAM/VRAM *budget* — just single-tenancy.
- [ ] **Desktop vs. mobile catalog split** — models split by `_REPO_ID` (server, 4-bit GPU) vs. `_GGUF_SOURCE` (in-app), but that's a *where it runs* distinction, not the hardware-aware gating layer the spec describes. No `platform_support` field, no per-device labelling.
- [x] **Orchestration tab** — a working Model Council, see "Orchestration" above. Only the manifest-preset and multi-round pieces remain.
- [ ] **Code tab** — still the placeholder add-on ([`addons/placeholder_addon.dart`](app/lib/addons/placeholder_addon.dart)): owns a sidebar panel and a full main pane, marked "under construction". No behavior yet.
- [x] **Plugin/add-on interface contract** (spec #3) — landed; see "Add-on architecture" above. One capability so far (`model_pool`); `memory` is deliberately absent until the SQLite-vs-PocketBase question below is settled, and adding it is a new enum case plus a getter, not a redesign.

### Not started

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
