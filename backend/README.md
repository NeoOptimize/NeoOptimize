---
title: NeoOptimasi AI Backend
emoji: 🛠
colorFrom: blue
colorTo: gray
sdk: docker
app_port: 7860
pinned: false
---

# NeoOptimasi AI Backend

FastAPI boilerplate untuk Hugging Face Spaces Docker SDK yang menghubungkan Neo AI ke Supabase.

## Komponen

- `app/main.py`: entrypoint FastAPI.
- `app/services/ai_agent.py`: Neo AI service dengan Hugging Face Inference fallback.
- `app/services/supabase_client.py`: repository untuk registrasi client, telemetry, health, action log, dan remote command.
- `app/api/v1/endpoints/*`: REST dan WebSocket endpoint.

## Environment

Gunakan `.env.example` sebagai template. Jangan commit service role key atau token Hugging Face ke git.

## Local Run

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 7860
```

## Hugging Face Space

Push isi folder `backend/` ke repo Hugging Face Space yang memakai `sdk: docker`, lalu set secrets berikut:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `HF_TOKEN`
- `HF_MODEL_ID`
