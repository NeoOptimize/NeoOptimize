import os
from dotenv import load_dotenv
from functools import lru_cache

load_dotenv()

@lru_cache
def get_settings():
    """Load environment variables safely."""
    required_vars = {
        "HF_TOKEN": "Hugging Face Token tidak ditemukan. Pastikan HF_TOKEN di-set di .env.",
        "SUPABASE_URL": "Supabase URL tidak ditemukan.",
        "SUPABASE_KEY": "Supabase Service Role Key tidak ditemukan.",
        "CLIENT_API_KEY": "Client API Key diperlukan untuk autentikasi.",
    }

    for var, err_msg in required_vars.items():
        if not os.getenv(var):
            raise ValueError(f"Error: {err_msg}")

    class Settings:
        # Auth & DB
        HF_TOKEN: str = os.getenv("HF_TOKEN")
        SUPABASE_URL: str = os.getenv("SUPABASE_URL")
        SUPABASE_KEY: str = os.getenv("SUPABASE_KEY")
        CLIENT_API_KEY: str = os.getenv("CLIENT_API_KEY")

        # System & Model
        MODEL_NAME: str = os.getenv("MODEL_NAME", "microsoft/phi-2")
        DEVICE: str = "cuda" if torch.cuda.is_available() else "cpu"
        
        # Monitoring Thresholds
        CPU_THRESHOLD: int = 90
        RAM_THRESHOLD: int = 95
        
        # Runtime
        DEBUG: bool = os.getenv("DEBUG", "False").lower() == "true"
        VERSION: str = "1.0.0"

    return Settings()

settings = get_settings()