"""Servicio de Asistente de IA de DOPA usando el SDK oficial de OpenAI (`from openai import OpenAI`).

Se conecta a NVIDIA NIM (`https://integrate.api.nvidia.com/v1`) o cualquier proveedor
compatible con OpenAI Chat Completions, inyectando el contexto real del usuario desde
PostgreSQL (tareas pendientes, micro-pasos, dopamina y nivel de energía).
"""

import os
import re
from datetime import datetime
from typing import Any, Optional

from fastapi import HTTPException, status
from openai import OpenAI
from sqlalchemy.orm import Session

from app.data.repositories import RegistroPersonalRepository, TareaRepository
from app.domain.models import Usuario
from app.transfer.dtos import (
    AIActionDTO,
    AIChatMessageDTO,
    AIChatRequestDTO,
    AIChatResponseDTO,
    AIStatusResponseDTO,
)

DEFAULT_AI_BASE_URL = "https://integrate.api.nvidia.com/v1"
DEFAULT_AI_MODEL = "meta/muse-glimmer-30b"

SYSTEM_PROMPT_BASE = """
Eres el asistente de productividad integrado en DOPA, una aplicación móvil diseñada para personas con TDAH que buscan gestionar sus tareas de forma empática y sin presión.

Tu personalidad:
- Eres amigable, empático y motivador, nunca juzgas ni presionas.
- Usas un tono cálido y conversacional, como un amigo que te ayuda a organizarte.
- Prefieres sugerencias suaves y de baja fricción: "poquito a poquito".
- Cuando recomiendas tareas, explicas brevemente por qué (ej: "es rápida y te dará un impulso de dopamina").
- Nunca usas lenguaje técnico ni abrumador.
- Respondes siempre en español.
- Mantén tus respuestas concisas y útiles (máximo 3-4 párrafos cortos).

Tu rol:
- Ayudar al usuario a decidir qué tarea hacer primero.
- Organizar y priorizar tareas según urgencia, dificultad y energía del usuario.
- Sugerir un plan para el día o dividir una tarea grande en micro-pasos pequeños.
- Recomendar cuándo tomar un break suave.
- Analizar las tareas pendientes y completadas reales del usuario para dar feedback.
- Nunca inventes que el usuario ya tiene tareas que no aparecen en el contexto; si propones una nueva, aclara que es una sugerencia.

Formato de respuesta:
- Usa emojis con moderación para hacer la conversación amigable.
- Cuando menciones tareas específicas del usuario, escríbelas entre comillas.
- Para listas, usa viñetas simples.
""".strip()


class AIAssistantService:
    """Servicio de chat con IA usando `from openai import OpenAI`."""

    def __init__(self, db: Session) -> None:
        self.db = db
        self.tarea_repo = TareaRepository(db)
        self.registro_repo = RegistroPersonalRepository(db)
        self.base_url = os.getenv("AI_API_BASE_URL", DEFAULT_AI_BASE_URL).strip() or DEFAULT_AI_BASE_URL
        self.api_key = os.getenv("AI_API_KEY", "").strip()
        self.model = os.getenv("AI_MODEL", DEFAULT_AI_MODEL).strip() or DEFAULT_AI_MODEL

    def get_status(self) -> AIStatusResponseDTO:
        """Retorna el estado de configuración del proveedor de IA sin exponer la API key."""
        return AIStatusResponseDTO(
            configured=bool(self.api_key),
            base_url=self.base_url,
            model=self.model,
        )

    def _build_user_context(self, usuario: Usuario, section: Optional[str]) -> str:
        tareas, _ = self.tarea_repo.list_by_user(id_usuario=usuario.id, limit=50, offset=0)
        pendientes = [t for t in tareas if not t.completada]
        completadas = [t for t in tareas if t.completada]

        energia_hoy = "media"
        registros, _ = self.registro_repo.list_by_user(id_usuario=usuario.id, limit=10, offset=0)
        for reg in registros:
            nombre_reg = (reg.nombre or "").strip()
            if nombre_reg.lower().startswith("energía diaria:"):
                energia_hoy = nombre_reg.split(":", 1)[1].strip()
                break

        lines = [
            "=== CONTEXTO REAL DEL USUARIO EN DOPA (PostgreSQL) ===",
            f"Fecha y hora actual: {datetime.now().isoformat(timespec='minutes')}",
            f"Usuario: {usuario.nombre} (Nivel {usuario.nivel}, Dopamina acumulada: {usuario.puntos} pts)",
            f"Energía reportada hoy: {energia_hoy}",
            f"Sección actual en la app: {section or 'Inicio'}",
            f"Resumen de tareas: {len(pendientes)} pendientes, {len(completadas)} completadas de {len(tareas)} totales.",
            "",
        ]

        if pendientes:
            lines.append("## Tareas Pendientes:")
            for idx, tarea in enumerate(pendientes, start=1):
                prio = tarea.prioridad.value if hasattr(tarea.prioridad, "value") else str(tarea.prioridad)
                lines.append(f'{idx}. [ID {tarea.id}] "{tarea.titulo}" (Prioridad: {prio})')
                if tarea.descripcion:
                    lines.append(f"   Nota: {tarea.descripcion}")
                subs = list(tarea.subtareas or [])
                if subs:
                    hechas = sum(1 for s in subs if s.completada)
                    lines.append(f"   Micro-pasos ({hechas}/{len(subs)}):")
                    for s in subs:
                        marca = "✓" if s.completada else "○"
                        lines.append(f"     {marca} {s.descripcion}")
        else:
            lines.append("## Tareas Pendientes: Ninguna pendiente por ahora.")

        if completadas:
            lines.append("")
            lines.append("## Tareas Completadas:")
            for tarea in completadas[:10]:
                lines.append(f'- ✓ "{tarea.titulo}"')

        return "\n".join(lines)

    @staticmethod
    def _clean_reply(raw_text: str) -> str:
        """Elimina posibles bloques internos `<think>...</think>` si el modelo razona en texto."""
        cleaned = re.sub(r"<think>.*?</think>", "", raw_text, flags=re.DOTALL).strip()
        return cleaned or raw_text.strip()

    @staticmethod
    def _extract_actions(reply_text: str) -> list[AIActionDTO]:
        actions: list[AIActionDTO] = []
        lower = reply_text.lower()

        if any(
            k in lower
            for k in ("podrías agregar", "te sugiero crear", "nueva tarea", "podrías crear", "añadir una tarea")
        ):
            actions.append(
                AIActionDTO(
                    type="agregarTarea",
                    label="➕ Crear micro-tarea",
                    payload={},
                )
            )
        if any(k in lower for k in ("organizar", "priorizar", "reordenar", "plan para", "tareas")):
            actions.append(
                AIActionDTO(
                    type="organizarTareas",
                    label="📋 Ir a Mis Tareas",
                    payload={},
                )
            )
        if any(k in lower for k in ("break", "descanso", "pausa", "descansar", "respir")):
            actions.append(
                AIActionDTO(
                    type="tomarBreak",
                    label="☁️ Tomar un break",
                    payload={},
                )
            )
        if any(k in lower for k in ("empezar", "iniciar", "enfocarte", "concentrar", "enfoque")):
            actions.append(
                AIActionDTO(
                    type="iniciarFoco",
                    label="🎯 Iniciar enfoque",
                    payload={},
                )
            )
        return actions

    def _create_client(self) -> OpenAI:
        return OpenAI(
            base_url=self.base_url,
            api_key=self.api_key,
            timeout=120.0,
            max_retries=1,
        )

    def chat(self, usuario: Usuario, dto: AIChatRequestDTO) -> AIChatResponseDTO:
        """Envía el mensaje + historial + contexto real de PostgreSQL al modelo OpenAI/NIM."""
        if not self.api_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="El asistente de IA no tiene configurada AI_API_KEY en el servidor Docker.",
            )

        context_prompt = self._build_user_context(usuario, dto.section)
        messages: list[dict[str, Any]] = [
            {
                "role": "system",
                "content": (
                    f"{SYSTEM_PROMPT_BASE}\n"
                    "IMPORTANTE: Sé directo y conciso (máximo 2 párrafos cortos, sin extenderte demasiado).\n\n"
                    f"{context_prompt}"
                ),
            }
        ]

        # Últimos 6 mensajes del historial previo para mantener respuestas ágiles
        for item in dto.history[-6:]:
            if isinstance(item, AIChatMessageDTO) and item.content.strip():
                messages.append({"role": item.role, "content": item.content.strip()})

        messages.append({"role": "user", "content": dto.message.strip()})

        try:
            client = self._create_client()
            completion = client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=1,
                top_p=0.95,
                max_tokens=768,
                stream=True,
            )

            content_parts: list[str] = []
            # Soporta tanto respuesta en streaming (chunks) como respuesta directa (mocks/stream=False)
            if hasattr(completion, "choices"):
                if completion.choices and completion.choices[0].message:
                    content_parts.append(completion.choices[0].message.content or "")
            else:
                for chunk in completion:
                    if not getattr(chunk, "choices", None):
                        continue
                    delta = chunk.choices[0].delta
                    if delta is not None and getattr(delta, "content", None):
                        content_parts.append(delta.content)

            raw_content = "".join(content_parts)
            reply = self._clean_reply(raw_content) or (
                "No pude generar una respuesta en este momento. ¿Intentamos de nuevo?"
            )
            return AIChatResponseDTO(
                reply=reply,
                model=self.model,
                actions=self._extract_actions(reply),
            )
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Error al comunicarse con el proveedor de IA: {exc}",
            ) from exc
