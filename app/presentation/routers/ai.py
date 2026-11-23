"""Controlador REST del Asistente de IA (`/api/v1/ai`) — Proyecto DOPA."""

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.ai_service import AIAssistantService
from app.data.database import get_db
from app.domain.models import Usuario
from app.presentation.dependencies import get_current_user
from app.transfer.dtos import AIChatRequestDTO, AIChatResponseDTO, AIStatusResponseDTO

router = APIRouter(prefix="/api/v1/ai", tags=["10. Asistente de IA (OpenAI / NVIDIA NIM)"])


@router.get(
    "/status",
    response_model=AIStatusResponseDTO,
    status_code=status.HTTP_200_OK,
    summary="Verificar si el asistente de IA está configurado en el servidor",
)
def ai_status(
    db: Session = Depends(get_db),
) -> AIStatusResponseDTO:
    return AIAssistantService(db).get_status()


@router.post(
    "/chat",
    response_model=AIChatResponseDTO,
    status_code=status.HTTP_200_OK,
    summary="Enviar consulta al asistente de IA DOPA con contexto real de PostgreSQL",
)
def ai_chat(
    dto: AIChatRequestDTO,
    usuario: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AIChatResponseDTO:
    return AIAssistantService(db).chat(usuario, dto)
