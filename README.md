# Multi-AI

A hybrid Python/Dart edge computing platform for managing and running multiple AI models locally, with a Flutter mobile/desktop frontend.

## Structure

```
MULTI-AI/
├── Multi-AI/multi_ai/   # Python package — Cython model stubs and utilities
│   └── models/          # 37 model stubs (deepmind, qwen3, falcon, llama, etc.)
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

## Python Backend

Install the package (editable):

```bash
pip install -e .
```

Run a model directly:

```bash
python -m multi_ai.models.qwen3
```

Run tests:

```bash
pip install pytest
pytest -q
```

## TODO

- [ ] Fix `.gitignore` — exclude `venv/`, `__pycache__/`, compiled `.so` binaries, and `.c` build artifacts
- [ ] Flesh out at least 2–3 real model implementations end-to-end (currently most `.pyx` files are placeholder stubs)
- [ ] Wire up the API layer so the Flutter frontend (`app/lib/api_tester.dart`) talks to a real backend handler
- [ ] Fix `models/__init__.pyx` to export all 37 models, not just 8 (and remove the duplicate `deepseek_v3` import)

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
