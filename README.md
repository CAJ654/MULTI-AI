# Multi-AI

A hybrid Python/TypeScript edge computing platform for managing and running multiple AI models locally, with a React web frontend and planned mobile support via Capacitor.

## Structure

```
MULTI-AI/
├── Multi-AI/multi_ai/   # Python package — Cython model stubs and utilities
│   └── models/          # 37 model stubs (deepmind, qwen3, falcon, llama, etc.)
├── src/                 # React/TypeScript frontend
├── my-python-app/       # Platformatic Python ASGI backend
└── tests/               # Import validation tests
```

## Frontend (Bun + React)

Install dependencies:

```bash
bun install
```

Start dev server:

```bash
bun dev
```

Run for production:

```bash
bun start
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
- [ ] Wire up the API layer so the React frontend (`APITester.tsx`) talks to a real backend handler
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

### Workflow Customizer

- Create a `workflows` PocketBase collection.
- When a user saves a workflow in the React Flow editor, the JSON is persisted to this collection.
- PocketBase's built-in Realtime Subscriptions sync changes across devices instantly — no custom sync code needed.

### Why PocketBase over Dify

- **Minimal footprint**: One binary vs. a full Docker Compose stack (Postgres, Redis, etc.) — runs on a Raspberry Pi or a $4/month VPS.
- **Flutter SDK**: Fetching model data is a one-liner: `pb.collection('models').getFullList()`
- **Built-in auth**: Email/password and OAuth (Google, Apple) out of the box.
