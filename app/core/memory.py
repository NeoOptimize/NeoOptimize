import logging
from typing import List
from datetime import datetime
from sentence_transformers import SentenceTransformer
from app.services.supabase_client import get_supabase

logger = logging.getLogger(__name__)

_embedder = None

def get_embedder():
    global _embedder
    if _embedder is None:
        _embedder = SentenceTransformer('all-MiniLM-L6-v2')
        logger.info("Embedding model loaded")
    return _embedder

def retrieve_relevant_context(query: str, client_id: str = None, top_k: int = 3) -> List[str]:
    try:
        embedder = get_embedder()
        query_emb = embedder.encode(query).tolist()
        supabase = get_supabase()

        # Asumsikan ada fungsi RPC `match_memory` dengan parameter opsional client_id
        params = {
            'query_embedding': query_emb,
            'match_threshold': 0.7,
            'match_count': top_k,
            'client_id_filter': client_id
        }
        resp = supabase.rpc('match_memory', params).execute()
        return [
            f"Related past interaction: {row['user_message']} -> {row['ai_response']}"
            for row in resp.data
        ]
    except Exception as e:
        logger.error(f"Memory retrieval error: {e}")
        return []

def store_interaction(user_message: str, ai_response: str, client_id: str = None):
    try:
        embedder = get_embedder()
        text = f"User: {user_message}\nAI: {ai_response}"
        embedding = embedder.encode(text).tolist()
        data = {
            "user_message": user_message,
            "ai_response": ai_response,
            "embedding": embedding,
            "client_id": client_id,
            "created_at": datetime.utcnow().isoformat()
        }
        supabase = get_supabase()
        supabase.table("memory").insert(data).execute()
    except Exception as e:
        logger.error(f"Store memory error: {e}")