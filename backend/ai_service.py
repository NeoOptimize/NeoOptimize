from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from uuid import uuid4
from typing import Any, Optional
import os
from dotenv import load_dotenv

load_dotenv()

router = APIRouter()


class ChatRequest(BaseModel):
    message: str
    client_id: Optional[str] = None
    user_id: Optional[str] = None


class ChatResponse(BaseModel):
    reply: str
    correlation_id: str


# Simple LLM adapter: prefer HuggingFace Inference API via huggingface_hub, fallback to local stub
HF_TOKEN = os.getenv("HF_TOKEN")
HF_MODEL_ID = os.getenv("HF_MODEL_ID") or "gpt2"

try:
    from huggingface_hub import InferenceClient
    _hf_client = InferenceClient(token=HF_TOKEN) if HF_TOKEN else None
except Exception:
    _hf_client = None


def _call_hf_model(prompt: str) -> str:
    """Call HF Inference API (via huggingface_hub) if available. Returns generated text or raises."""
    if not _hf_client or not HF_MODEL_ID:
        raise RuntimeError("HuggingFace client not configured")

    try:
        # text_generation returns a list of generation dicts in many versions
        resp = _hf_client.text_generation(model=HF_MODEL_ID, inputs=prompt, parameters={"max_new_tokens": 300})
        # resp may be a list or dict depending on model/adapter
        if isinstance(resp, list) and resp:
            first = resp[0]
            if isinstance(first, dict) and "generated_text" in first:
                return first["generated_text"]
            if isinstance(first, dict) and "text" in first:
                return first["text"]
            return str(first)
        if isinstance(resp, dict) and "generated_text" in resp:
            return resp["generated_text"]
        return str(resp)
    except Exception as e:
        raise


@router.post("/ai/chat", response_model=ChatResponse)
async def ai_chat(req: ChatRequest):
    if not req.message or not req.message.strip():
        raise HTTPException(status_code=400, detail="message required")

    user_msg = req.message.strip()

    # Try HF model first
    if _hf_client:
        try:
            generated = _call_hf_model(user_msg)
            # Sanitise/trim reply
            reply = (generated or "").strip()
            if not reply:
                reply = "Neo AI tidak bisa menghasilkan jawaban saat ini."
            return ChatResponse(reply=reply, correlation_id=str(uuid4()))
        except Exception:
            # fallthrough to fallback stub
            pass

    # Fallback interactive stub
    reply = (
        f"Hai — aku Neo AI. Kamu berkata: '{user_msg}'. Aku bisa membantu menganalisa kondisi sistem, "
        "membuat rencana aksi, atau menjalankan optimasi jika kamu setuju. Apa yang ingin kamu lakukan selanjutnya?"
    )

    return ChatResponse(reply=reply, correlation_id=str(uuid4()))
