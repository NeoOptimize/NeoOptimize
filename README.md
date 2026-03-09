---
title: NeoOptimasi AI
emoji: ⚙️
colorFrom: blue
colorTo: gray
sdk: docker
app_port: 7860
pinned: false
---

# NeoOptimasi AI

Hugging Face Space Docker untuk backend FastAPI NeoOptimasi AI yang terhubung ke Supabase.

## Runtime

Space ini build dari folder `backend/` dan menjalankan `uvicorn app.main:app` pada port `7860`.

## Secrets yang wajib di Space

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `HF_TOKEN`
- `HF_MODEL_ID`
