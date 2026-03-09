from fastapi import APIRouter

commands_router = APIRouter()
voice_router = APIRouter()
telemetry_router = APIRouter()

@commands_router.get("/")
async def read_root():
    return {"router": "commands"}
# Add endpoints in specific files later