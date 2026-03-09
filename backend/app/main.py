import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import gradio as gr
from dotenv import load_dotenv

load_dotenv()

from app.api.v1.endpoints import auth, commands, telemetry, websocket
from app.core.agent import agent_executor
from app.core.memory import retrieve_relevant_context, store_interaction
from app.core.monitor import AutonomousMonitor
from app.services.supabase_client import get_supabase
from app.utils.logger import setup_logging
from typing import List
import logging

setup_logging()
logger = logging.getLogger(__name__)

app = FastAPI(title="Neo AI Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(commands.router, prefix="/api/v1/commands", tags=["commands"])
app.include_router(telemetry.router, prefix="/api/v1/telemetry", tags=["telemetry"])
app.include_router(websocket.router, prefix="/api/v1/ws", tags=["websocket"])

@app.get("/")
async def root():
    return {"message": "Neo AI Backend is running"}

# ========== GRADIO CHAT INTERFACE ==========
def chat_with_memory(message: str, history: List[List[str]], client_id: str = None) -> str:
    try:
        context = retrieve_relevant_context(message, client_id=client_id)
        if context:
            context_str = "\n".join(context)
            message_with_context = f"Konteks dari percakapan sebelumnya:\n{context_str}\n\nPertanyaan: {message}"
        else:
            message_with_context = message

        # Untuk sementara, client_id tidak digunakan di agent karena tools memerlukannya di input.
        # Kita bisa menambahkan client_id ke dalam prompt atau menggunakan cara lain.
        # Untuk demo, kita asumsikan client_id disertakan dalam input pengguna.
        # Dalam production, client_id harus didapat dari sesi/login.
        response = agent_executor.run(input=message_with_context)
        store_interaction(message, response, client_id=client_id)
        return response
    except Exception as e:
        logger.exception("Chat error")
        return f"Terjadi kesalahan: {str(e)}"

def respond_text(message, chat_history):
    if not message.strip():
        return "", chat_history
    # Di sini kita bisa mengambil client_id dari suatu tempat (misal dari sesi)
    # Untuk sementara hardcode None
    bot_message = chat_with_memory(message, chat_history, client_id=None)
    chat_history.append((message, bot_message))
    return "", chat_history

with gr.Blocks(title="Neo AI Super Cerdas", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🤖 Neo AI - Asisten Sistem Windows Super Cerdas")
    chatbot = gr.Chatbot()
    msg = gr.Textbox(label="Pesan Anda", placeholder="Ketik perintah...")
    clear = gr.Button("Hapus Percakapan")

    msg.submit(respond_text, [msg, chatbot], [msg, chatbot])
    clear.click(lambda: None, None, chatbot, queue=False)

app = gr.mount_gradio_app(app, demo, path="/")

# ========== STARTUP / SHUTDOWN ==========
monitor = None

@app.on_event("startup")
async def startup_event():
    global monitor
    try:
        supabase = get_supabase()
        supabase.table("clients").select("id").limit(1).execute()
        logger.info("Supabase connection successful")
    except Exception as e:
        logger.error(f"Supabase connection failed: {e}")

    monitor = AutonomousMonitor(check_interval=60)
    logger.info("AutonomousMonitor started")

@app.on_event("shutdown")
async def shutdown_event():
    if monitor:
        monitor.stop()