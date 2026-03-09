"""
NeoAI Main Application Entry Point
FastAPI Server with Gradio Interface & REST API
"""

import os
import sys
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Ensure app path is in sys.path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.core.config import settings
from app.core.logger import setup_logging
from app.core.security import SecurityService

# Import Routers (Placeholders for now, will connect to real routers later)
from app.api.v1.routers import commands_router, voice_router, telemetry_router

logger = setup_logging()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle (startup/shutdown)."""
    logger.info("=" * 50)
    logger.info(f"🚀 NeoAI Backend v{settings.VERSION} Starting...")
    logger.info(f"📍 Device: {settings.DEVICE}")
    logger.info(f"🤖 Model: {settings.MODEL_NAME}")
    
    # Initialize Database Connection (Lazy load in supabase_client)
    try:
        from app.services.supabase_client import get_supabase_client
        await get_supabase_client()
        logger.info("✅ Supabase Connected Successfully")
    except Exception as e:
        logger.error(f"❌ Database Connection Failed: {e}")

    yield

    logger.info("🛑 NeoAI Backend Shutting down...")

app = FastAPI(
    title="NeoOptimasi AI API",
    description="AI-Powered Windows System Optimization Platform",
    version=settings.VERSION,
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add Headers dependency to check API Key globally or per endpoint
async def verify_api_key(request: Request):
    auth_header = request.headers.get("X-API-Key")
    if not auth_header or auth_header != settings.CLIENT_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")

# Mount API Routers
app.include_router(commands_router, prefix="/api/v1", tags=["Commands"])
app.include_router(voice_router, prefix="/api/v1", tags=["Voice"])
app.include_router(telemetry_router, prefix="/api/v1", tags=["Telemetry"])

@app.get("/health")
async def health_check():
    """Basic health check for load balancers or monitoring."""
    return {
        "status": "healthy",
        "timestamp": "2024-01-01T00:00:00Z", # Update dynamically
        "version": settings.VERSION,
        "service": "NeoAI Backend"
    }

# Placeholder for direct usage without routes
class ToolInput(BaseModel):
    tool: str
    params: dict

@app.post("/command/direct")
async def execute_direct_tool(data: ToolInput):
    """Direct tool execution helper (bypasses queue)."""
    logger.info(f"Executing direct command: {data.tool}")
    return {"status": "executed", "tool": data.tool}

if __name__ == "__main__":
    import uvicorn
    host = "0.0.0.0"
    port = int(os.getenv("PORT", 7860))
    
    logger.info(f"Starting server on {host}:{port}")
    uvicorn.run(app, host=host, port=port)