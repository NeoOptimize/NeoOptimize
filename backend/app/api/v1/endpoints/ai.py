from fastapi import APIRouter

from app.models.schemas import AIChatRequest, AIChatResponse, AIFeedbackRequest, AIFeedbackResponse
from app.services.ai_agent import get_ai_agent

router = APIRouter()


@router.post("/chat", response_model=AIChatResponse, summary="Talk to Neo AI")
def chat(payload: AIChatRequest) -> AIChatResponse:
    agent = get_ai_agent()
    return agent.handle_chat(payload)


@router.post("/feedback", response_model=AIFeedbackResponse, summary="Store feedback for an AI memory")
def feedback(payload: AIFeedbackRequest) -> AIFeedbackResponse:
    agent = get_ai_agent()
    return agent.record_feedback(payload)
