# Multi-AI (project)

This repository contains several small model stubs and utilities organized as a
Python package for development and testing.

Structure
- multi_ai/ - package
  - models/ - model stubs (deepmind, qwen3, etc.)
- tests/ - simple import tests

Quick start

1. Install editable package (optional):

```powershell
pip install -e .
```

2. Run a module directly:

```powershell
python -m multi_ai.models.qwen3
```

3. Run tests (pytest):

```powershell
pip install pytest
pytest -q
```



## TODO

- [ ] Fix `.gitignore` — exclude `venv/`, `__pycache__/`, compiled `.so` binaries, and `.c` build artifacts
- [ ] Flesh out at least 2–3 real model implementations end-to-end (currently most `.pyx` files are placeholder stubs)
- [ ] Wire up the API layer so the React frontend (`APITester.tsx`) talks to a real backend handler
- [ ] Fix `models/__init__.pyx` to export all 37 models, not just 8 (and remove the duplicate `deepseek_v3` import)

---

plan
In this setup, PocketBase becomes your Control Plane, handling user authentication, model metadata, and workflow synchronization.
Updated Text Stack (PocketBase Edition)
| Category | Technology | Role |
|---|---|---|
| Mobile Core | Flutter | Cross-platform UI and native hardware bridges. |
| Edge Backend | PocketBase | Replaces Dify for Auth, Model Registry, and Workflow Sync. |
| Local AI Engine | MLC LLM | Direct NPU/GPU access for model execution. |
| Storage (Logic) | PocketBase Collections | Stores metadata, user profiles, and workflow JSONs. |
| Storage (Large Files) | S3-Compatible (R2) | Linked to PocketBase for hosting 5GB+ model files. |
How PocketBase manages your Models
You don't want to store the 5GB model files inside the PocketBase SQLite database (it would make the database massive and slow). Instead, you use PocketBase’s S3 integration:
 * S3 Linking: In the PocketBase Admin UI (Settings > Files storage), you toggle on "S3 Storage" and enter your Cloudflare R2 credentials.
  * Model Collection: You create a collection called models:
     * name (Text)
        * version (Text)
           * requirements (JSON: RAM, Disk space)
              * model_file (File: This is where you upload the .gguf or .mlc file).
               * The Result: When you upload a model via the PocketBase dashboard, it automatically puts the file in your S3 bucket but keeps a record (metadata) in your local database. Your app then fetches this list and downloads the file via a clean URL.
               The Workflow "Customizer" Logic
               To allow users to build Dify-style workflows on the edge:
                * Workflow Collection: Create a PocketBase collection called workflows.
                 * JSON Schema: When a user finishes dragging nodes in your React Flow editor, the resulting JSON is saved to the workflows collection in PocketBase.
                  * Realtime Sync: PocketBase’s built-in Realtime Subscriptions mean that if a user updates a workflow on their tablet, the change pushes to their phone instantly without you writing any custom sync code.
                  Why PocketBase is better than Dify for this specific plan:
                   * Minimal Footprint: Dify requires a whole Docker Compose stack (Postgres, Redis, etc.). PocketBase is one file. You can run your entire backend on a $4/month VPS or even a Raspberry Pi.
                    * Easier Mobile SDK: PocketBase has a first-class Flutter SDK. Authenticating users and fetching model data is a simple 3-line function:
                       final records = await pb.collection('models').getFullList();

                        * Simplified Auth: It handles email/password and OAuth (Google, Apple) out of the box, which you’ll need if you want users to save their "Custom AIs" to an account.
                        A Critical Implementation Tip:
                        Proxied Downloads: By default, PocketBase proxies file downloads through its own server. For 5GB model files, this will crash your server's RAM.
                         * Solution: In your app, don't use the direct file URL from the PocketBase SDK. Instead, use the S3 direct link or generate a "Presigned URL" so the phone downloads directly from the storage bucket to bypass the PocketBase server.
