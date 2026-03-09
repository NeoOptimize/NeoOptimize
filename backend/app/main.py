import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.endpoints import ai, auth, commands, health, telemetry, websocket
from app.core.config import get_settings
from app.services.supabase_client import get_supabase


def configure_logging() -> None:
    settings = get_settings()
    level = getattr(logging, settings.log_level.upper(), logging.INFO)
    logging.basicConfig(
        level=level,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_logging()
    logger = logging.getLogger("neooptimize.startup")

    try:
        get_supabase()
        logger.info("Supabase client initialized")
    except Exception as exc:
        logger.warning("Supabase initialization skipped: %s", exc)

    yield


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        debug=settings.debug,
        lifespan=lifespan,
    )

    allow_credentials = settings.allowed_origins != ["*"]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=allow_credentials,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
    app.include_router(ai.router, prefix="/api/v1/ai", tags=["ai"])
    app.include_router(telemetry.router, prefix="/api/v1/telemetry", tags=["telemetry"])
    app.include_router(health.router, prefix="/api/v1/health", tags=["health"])
    app.include_router(commands.router, prefix="/api/v1/commands", tags=["commands"])
    app.include_router(websocket.router, prefix="/api/v1/ws", tags=["websocket"])

    @app.get("/", summary="Backend info")
    async def root() -> dict[str, object]:
        return {
            "service": settings.app_name,
            "version": settings.app_version,
            "environment": settings.app_env,
            "features": [
                "client-registration",
                "telemetry-ingestion",
                "system-health",
                "remote-commands",
                "neo-ai-assistant",
                "websocket-monitoring",
            ],
        }

    @app.get("/healthz", summary="Liveness probe")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()
