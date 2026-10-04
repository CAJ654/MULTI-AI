# AI Tools Comparison: Major Vendors, Open-Source Options, and Implementation Methods

This document compares the AI models and developer tools from the major AI
companies, notes which parts are open source or open-weight, and describes
how each could be used in MULTI-AI for on-device inference.

> **Currency note.** This was written from information available up to
> January 2026. Model names, versions, licenses, and pricing change often.
> Check each vendor's current documentation and the license file in the
> model repository before relying on a specific detail.

## Terms Used

- **Open source**: the code is released under an OSI-approved license (MIT,
  Apache 2.0, and similar).
- **Open-weight**: the trained model weights can be downloaded and run, but
  the license may add restrictions (acceptable-use rules, user-count caps,
  or custom terms). Open-weight is not the same as open source.
- **Closed**: only available through a hosted API or product.

## 1. Vendor Comparison

| Vendor | Closed flagship | Open-weight family | Open-weight license | Open-source tooling | Relevance to MULTI-AI |
|---|---|---|---|---|---|
| **Google** | Gemini (API, Gemini app, Gemini CLI) | Gemma (Gemma 3, Gemma 3n for devices, CodeGemma, TxGemma, EmbeddingGemma) | Gemma Terms of Use (custom, not OSI) | Gemini CLI (Apache 2.0), JAX, MediaPipe LLM Inference | Gemma 3n and small Gemma variants are designed for phones and laptops. Already present in the model list (CodeGemma, TxGemma). |
| **OpenAI** | GPT-4o / GPT-5 family, ChatGPT, Codex (cloud) | gpt-oss-20b and gpt-oss-120b (released August 2025) | Apache 2.0 | Codex CLI (Apache 2.0), Agents SDK (MIT), Whisper (MIT) | gpt-oss-20b is the most relevant OpenAI option for local use. Its MoE design keeps active parameters low. Needs about 16 GB of memory when quantized. |
| **Microsoft** | Copilot, Microsoft 365 Copilot, Phi Silica on Copilot+ PCs (NPU) | Phi-3 / Phi-4 family (Phi-4-mini, Phi-4-multimodal, Phi-4-reasoning) | MIT | VS Code (MIT), GitHub Copilot Chat extension (open source), ONNX Runtime and ONNX Runtime GenAI (MIT), Foundry Local, BitNet (1-bit inference, MIT) | Phi models are small and efficient, so they fit 12 GB VRAM well. ONNX Runtime is a strong option for Windows-native inference. |
| **Anthropic** | Claude (Opus, Sonnet, Haiku families), Claude Code, Claude apps | None. No open-weight Claude models. | n/a | Model Context Protocol (MCP, open specification and SDKs), Agent Skills format | Claude is reached through the API, not locally. MCP is useful for connecting any model to external tools. |
| **Meta** | Meta AI (app and web) | Llama 3.x, Llama 4 (Scout and Maverick, mixture-of-experts) | Llama Community License (open-weight, not OSI, with user-count and acceptable-use terms) | PyTorch (BSD), Llama Stack | Llama 3.x 8B is a common local model. Many tools default to Llama-format models. |
| **Mistral AI** | Mistral Medium / Large (API) | Mistral Small, Ministral, Devstral (coding agent), Magistral (reasoning) | Mostly Apache 2.0 for smaller open models; some larger ones use other terms | Mistral SDKs, vLLM support | Ministral and small Mistral models are practical on 12 GB VRAM with 4-bit quantization. Devstral is aimed at coding. |
| **Alibaba (Qwen)** | Qwen-Max (API) | Qwen3 (dense and MoE), Qwen3-Coder, Qwen2.5-Coder | Apache 2.0 (for most open Qwen models) | Qwen-Agent (Apache 2.0) | Strong open-weight range from 0.5B to 30B+. Already in the model list (Qwen3, Qwen2.5-Coder). |
| **DeepSeek** | DeepSeek API (V3 / R1 family) | DeepSeek-R1 and R1 distills (Qwen and Llama bases), DeepSeek-V3 (large) | MIT (R1 and distills follow the base model's license for those bases) | DeepSeek-Coder | R1 distills (1.5B to 32B) are practical locally. Already in the model list (DeepSeek R1 Distill). |
| **TII (Falcon)** | n/a | Falcon 3, Falcon-H1 | Falcon license (Apache-based, with acceptable-use terms) | n/a | Falcon 3 and H1 are small enough for local use. Already in the model list. |
| **IBM** | watsonx (enterprise) | Granite 3.x / 4.x | Apache 2.0 | Granite Docs and cookbooks | Permissive license and enterprise-oriented; good for business use. |
| **NVIDIA** | NIM microservices | Nemotron family | NVIDIA Open Model License (permissive, custom terms) | NeMo, TensorRT-LLM (Apache 2.0) | Strong GPU optimization. Useful if the RTX 5070 Ti is the main target. |

### Coding Agents and Developer Tools

| Tool | Vendor | Open source? | Works with local models? | Notes |
|---|---|---|---|---|
| **Claude Code** | Anthropic | No (proprietary CLI) | No (Claude models only) | Strong agentic coding. Cloud-only. |
| **Codex CLI** | OpenAI | Yes (Apache 2.0) | Yes, via OpenAI-compatible endpoints | Can point at a local server. |
| **Gemini CLI** | Google | Yes (Apache 2.0) | Limited (Gemini models) | Generous free tier through the Gemini API. |
| **GitHub Copilot** | Microsoft / GitHub | Partly (Copilot Chat extension and VS Code are open source; the service is closed) | Limited, with model choice in some plans | Most widely used IDE assistant. |
| **opencode** | Community (SST) | Yes (MIT) | Yes, any OpenAI-compatible endpoint, including Ollama and llama.cpp | Already used by this project (see recent commit "Code tool redone with opencode"). |
| **Aider** | Community | Yes (Apache 2.0) | Yes | Git-aware pair programming in the terminal. |
| **Cline / Roo Code** | Community | Yes (Apache 2.0) | Yes | VS Code agent extensions with local model support. |

### Product-Level Tools: Google and Anthropic

These are hosted products rather than models. Details come from public
launch coverage (checked October 2026); pricing and limits change often.

| Product | Vendor | What it does | Open source? | Local option? | Notes for MULTI-AI |
|---|---|---|---|---|---|
| **Gemini AI Studio** | Google | Browser IDE for prompting, testing, and building with Gemini models and the Gemini API. Released December 2023. | No | No (Gemini models are hosted). Its generated code can be exported. | Useful for prototyping prompts before moving them into the provider layer. Free tier with rate limits. |
| **Google Stitch** | Google Labs | Generates UI designs and frontend code from text prompts or images. Includes a design agent (Stitch Agent) that edits layouts from natural-language or voice requests. Free Labs experiment with a monthly generation limit. | No | No | Could produce UI mockups for the Flutter app. Output is HTML/CSS and design exports, so it needs manual adaptation to Flutter widgets. |
| **Google Opal** | Google Labs | No-code builder for AI mini-apps. Describe the app in plain language, and it creates a visual workflow that can be inspected and edited step by step. Public beta since July 2025, expanded to 160+ countries. | No | No | Good for quick workflow prototypes. Apps run on Google's servers, so they do not fit the on-device goal. |
| **Google Pomelli** | Google Labs with Google DeepMind | Free marketing tool for small businesses. Scans a website to build a "Business DNA" profile (colors, fonts, tone) and generates on-brand social posts, banners, and ad creatives. Public beta since October 2025. | No | No | Marketing-focused, so only loosely related to MULTI-AI. Its brand-profile idea could inform a similar style-extraction feature. |
| **Claude Design** | Anthropic Labs | Creates designs, prototypes, slides, and one-pagers from a prompt, screenshot, or codebase. Refined through conversation, comments, and direct edits. Hands off a bundle to Claude Code. Research preview since April 2026. | No | No | Pairs with Claude Code for design-to-code work. Requires a paid Claude plan. Could be a design step for the Flutter UI. |

Sources used for this section:

- [Pomelli, Google Labs blog](https://blog.google/innovation-and-ai/models-and-research/google-labs/pomelli/)
- [Opal expansion to 160+ countries, Google blog](https://blog.google/technology/google-labs/opal-expansion-160/)
- [Introducing Claude Design, Anthropic](https://www.anthropic.com/news/claude-design-anthropic-labs)
- [Google Labs overview, Wikipedia](https://en.wikipedia.org/wiki/Google_Labs)
- [Google AI Studio, Wikipedia](https://en.wikipedia.org/wiki/Google_AI_Studio)
- [Google Stitch guide, ALM Corp](https://almcorp.com/blog/google-stitch-complete-guide-ai-ui-design-tool-2026/)

## 1b. Side-Panel Workspaces: Artifacts and Canvas

These features show generated content (documents, code, web pages,
diagrams) in a panel beside the chat, so the user can view, edit, and run
it. Each vendor has one, and the table compares them. The "Claude
equivalent" column covers both the Claude feature and the closest match in
the other vendors' products. Details are from public coverage checked in
October 2026; these features change often.

| Feature | Vendor | What it does | Open source? | Local option? | Notes for MULTI-AI |
|---|---|---|---|---|---|
| **Claude Artifacts** | Anthropic | Renders code, HTML, SVG, React components, Mermaid diagrams, and Markdown in a sandboxed side panel. Supports inline edits. Artifacts can store up to 20 MB of persistent data, which can be personal, per-viewer, or shared. Live Artifacts (early 2026) can read data through MCP connectors. Claude Code Artifacts (beta, June 2026) publish coding sessions as HTML pages on private claude.ai URLs. | No | No | The closest existing example of an app-style output panel. The sandboxed preview pattern is worth copying. |
| **Gemini Canvas** | Google | Workspace in the Gemini app and in AI Mode in Search. Creates and edits documents, code, slides, web pages, infographics, quizzes, and Audio Overviews. Exports to Google Docs, Slides, or Colab. Available on the free tier. Google AI Pro and Ultra use a stronger model with a larger context window. | No | No | Good for documents and small apps. Output is tied to Google's export targets. |
| **ChatGPT Canvas** (OpenAI equivalent) | OpenAI | Side-by-side editor for writing and code, launched October 2024. Reports indicate it was removed from current models on May 28, 2026, and replaced by inline writing and code blocks in chat. Only legacy models support it for paid users until o3 retires. | No | No | Confirm current status on OpenAI's release notes before relying on it. Its replacement is inline blocks, not a panel. |
| **Claude's equivalent of Canvas** | Anthropic | Artifacts is Claude's answer to Canvas. It covers the same editing and preview role, and it adds publishing and data storage. | No | No | Same as Claude Artifacts above. |
| **LibreChat Artifacts** | Community (LibreChat) | Open-source chat UI that renders generated React, HTML, and Mermaid output in a panel. Works with any OpenAI-compatible model, including local ones. | Yes (MIT) | Yes | Strongest open-source match for Artifacts. Can run against llama.cpp or Ollama endpoints. |
| **Open WebUI** | Community (Open WebUI) | Self-hosted chat UI with a code and HTML preview option. Works with local models through Ollama or OpenAI-compatible servers. | Yes (source-available with branding terms; check the license file) | Yes | Alternative to LibreChat. Check its license terms before bundling. |

### Implementation notes for MULTI-AI

- **Sandboxed preview:** Render generated HTML or Mermaid output in a
  restricted WebView or iframe, with scripts limited and no access to local
  files. This matches the Artifacts approach and avoids running untrusted
  output inside the app.
- **Persistent storage:** Artifacts store data per viewer or shared. On this
  project, the equivalent is a local JSON or SQLite store next to the model
  registry. Nothing needs to leave the device.
- **Export:** Canvas exports to vendor-specific tools. A local version can
  export Markdown, HTML, or a file in the workspace instead.

Sources used for this section:

- [Claude Artifacts guide 2026, Albato](https://albato.com/blog/publications/how-to-use-claude-artifacts-guide)
- [Claude Live Artifacts guide, Eigent](https://www.eigent.ai/blog/claude-live-artifacts-guide)
- [Claude Code Artifacts, Digital Applied](https://www.digitalapplied.com/blog/claude-code-shareable-artifacts-live-web-pages-2026)
- [Gemini Canvas guide, Geeky Gadgets](https://www.geeky-gadgets.com/gemini-canvas-features-guide-2026/)
- [Canvas in AI Mode for all US users, WinBuzzer](https://winbuzzer.com/2026/03/05/google-gemini-canvas-ai-mode-all-us-users-coding-writing-xcxwbn/)
- [ChatGPT Canvas in 2026, AI Toolbox](https://www.ai-toolbox.co/chatgpt-management-and-productivity/how-to-use-chatgpt-canvas-guide-2026)
- [ChatGPT Canvas is gone, FelloAI](https://felloai.com/chatgpt-canvas/)

## 2. Hardware Fit (RTX 5070 Ti, 12 GB VRAM)

These are rough guides. Actual fit depends on context length, the runtime,
and the quantization format.

| Model size class | Example models | Fit at 4-bit quantization |
|---|---|---|
| 1B to 4B | Gemma 3 1B / 4B, Phi-4-mini, Qwen3 1.7B / 4B, Falcon 3 small | Comfortable. Fast. Good for background tasks. |
| 7B to 9B | Qwen3 8B, Llama 3.1 8B, Mistral / Ministral 8B, DeepSeek-R1-Distill-Qwen-7B, Gemma 3 12B (tight) | Fits fully on GPU. This is the usual sweet spot. |
| 12B to 14B | Phi-4 (14B), Gemma 3 12B, Qwen3 14B | Fits with shorter context. Consider a lower quant if speed drops. |
| 20B to 32B (MoE or dense) | gpt-oss-20b, Qwen3-30B-A3B (MoE), DeepSeek-R1-Distill-Qwen-32B | Partial GPU offload or tight fit. MoE models run faster than their size suggests. |
| 70B+ | Llama 3.3 70B, gpt-oss-120b | Not practical on 12 GB VRAM alone. Needs CPU offload or multi-GPU. |

The project's dev-machine notes already say 4-bit quantization is required
for 7B and larger models on this card.

## 3. Implementation Methods

### Local inference runtimes

| Method | License | Platforms | Best for | Notes |
|---|---|---|---|---|
| **llama.cpp** (`llama-server`) | MIT | Windows, macOS, Linux, Android, iOS | Lowest-level control, GGUF models, CPU and GPU | Exposes an OpenAI-compatible HTTP API. Good base for embedding in an app. |
| **Ollama** | MIT | Windows, macOS, Linux | Simple model management and serving | Built on llama.cpp. OpenAI-compatible API. Easiest for end users. |
| **LM Studio** | Proprietary freeware | Windows, macOS, Linux | GUI model browsing and testing | Not open source. Useful for trying models, less so for bundling. |
| **ONNX Runtime / ONNX Runtime GenAI** | MIT | Windows (DirectML, CUDA, NPU), others | Windows-native deployment and NPUs | Microsoft-maintained. Good match for Copilot+ PC hardware. |
| **Foundry Local** | Microsoft (see docs) | Windows, macOS | Microsoft-supported local model serving | Uses ONNX models. Check current license and availability. |
| **MLX / MLX-LM** | MIT | Apple Silicon | Mac builds | Not applicable to the Windows dev machine. |
| **vLLM** | Apache 2.0 | Linux, NVIDIA GPUs | High-throughput server inference | Overkill for a single-user desktop app. Good for a self-hosted server. |
| **Hugging Face Transformers + bitsandbytes** | Apache 2.0 / MIT | Python, CUDA | Research, fine-tuning, 4-bit loading | Used in the project's Python tooling for 4-bit loading. |
| **Transformers.js / WebLLM** | Apache 2.0 / MIT | Browser (WebGPU) | Running models in a web page | No install, but limited by browser memory and WebGPU support. |

### Integration patterns for MULTI-AI

1. **Local OpenAI-compatible server (recommended starting point).** Run
   llama.cpp `llama-server` or Ollama as a child process managed by the Flutter
   app (see `app/lib/backend_process.dart`). The Flutter app and coding tools
   (opencode, Aider, Codex CLI) all talk to `http://localhost:<port>/v1`. One
   client code path works for every local model and for hosted APIs that use
   the same format.

2. **Provider abstraction layer.** Define one interface such as
   `complete(prompt, options)` with adapters for:
   - Local llama.cpp / Ollama (OpenAI-compatible)
   - Hosted OpenAI, Anthropic, Google Gemini, Mistral, DeepSeek APIs
   - Microsoft ONNX Runtime (for NPU or DirectML on Windows)

   Route requests by policy: prefer local when the model fits and the task
   allows it, fall back to cloud for models that do not fit.

3. **Model registry.** Keep model definitions in one place with fields for
   vendor, license, quantization, VRAM estimate, context length, and
   capabilities (chat, code, reasoning, vision). The recent commit that added
   DeepSeek R1, Falcon, Qwen3, Qwen2.5-Coder, CodeGemma, and TxGemma definitions
   is the start of this pattern. Storing license per model supports the
   Gemma and Llama terms that differ from Apache and MIT.

4. **Tool and agent protocol.** Use MCP for tool access (file system, search,
   project tools) so any model in the registry can use the same tools. This
   avoids writing separate tool integrations for each vendor.

5. **Quantization pipeline.** For models without a published GGUF or ONNX
   build, convert and quantize with llama.cpp tools (GGUF, Q4_K_M or similar)
   or use an existing community build. Record the source and checksum.

### Cloud-only options

Anthropic Claude, OpenAI GPT and Codex (cloud), Google Gemini, and Microsoft
Copilot have no weights to download. They can only be reached through an API
or product, so they should sit behind the same provider layer as an
alternative to local inference. Their use sends data to the vendor, which is
the opposite of the project's on-device goal, so route to them only when the
user chooses or when a task needs the larger model.

## 4. Licensing Checklist Before Bundling a Model

- [ ] Is the license OSI-approved (MIT, Apache 2.0)? If not, read the custom terms (Gemma, Llama, NVIDIA Open Model License).
- [ ] Does the license allow redistribution inside an installer, or does the user download the weights separately?
- [ ] Are there user-count or revenue limits (Llama Community License)?
- [ ] Is an acceptable-use policy referenced, and does the app need to pass it on to users?
- [ ] Is the model's training data or base model under a different license (R1 distills, Falcon, Qwen bases)?

## 5. Open Questions

- Which models should be the default for each hardware tier?
- Should the app bundle any model, or download on first run?
- Which coding agent should be the default front end (opencode is current)?
- How should cloud fallback be presented to the user, and is it opt-in?
