"""Servicio de Asistente de IA de DOPA usando el SDK oficial de OpenAI (`from openai import OpenAI`).

Se conecta a NVIDIA NIM (`https://integrate.api.nvidia.com/v1`) o cualquier proveedor
compatible con OpenAI Chat Completions, inyectando el contexto real del usuario desde
PostgreSQL (nombre real, tareas pendientes, micro-pasos, dopamina y nivel de energía).
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
DEFAULT_AI_MODEL = "nvidia/nemotron-3.5-bolt-e4b"
FALLBACK_AI_MODELS = (
    "nvidia/nemotron-3.5-bolt-e4b",
    "minimaxai/minimax-m3.1-flash",
)

SYSTEM_PROMPT_BASE = """
Eres el asistente de productividad integrado en DOPA, una aplicación móvil diseñada para personas con TDAH que buscan gestionar sus tareas de forma empática y sin presión.

Tu personalidad:
- Eres amigable, empático y motivador, nunca juzgas ni presionas.
- Usas un tono cálido y conversacional, llamando al usuario por su nombre cuando corresponda.
- Prefieres sugerencias suaves y de baja fricción: "poquito a poquito".
- Cuando recomiendas tareas, explicas brevemente por qué (ej: "es rápida y te dará un impulso de dopamina").
- Nunca usas lenguaje técnico ni abrumador.
- Respondes siempre en español.
- Mantén tus respuestas concisas y útiles (máximo 2-3 párrafos cortos).

Tu rol:
- Ayudar al usuario a decidir qué tarea hacer primero.
- Organizar y priorizar tareas según urgencia, dificultad y energía del usuario.
- Sugerir un plan para el día o dividir una tarea grande en micro-pasos pequeños.
- Recomendar cuándo tomar un break suave.
- Analizar las tareas pendientes y completadas reales del usuario para dar feedback.
- Si el usuario aún no tiene tareas creadas, invítalo amablemente a crear su primera micro-tarea pequeña.
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
        configured_model = os.getenv("AI_MODEL", DEFAULT_AI_MODEL).strip() or DEFAULT_AI_MODEL
        # Reemplaza automáticamente modelos retirados de NVIDIA NIM (ej. meta/muse-glimmer-30b -> 410 Gone)
        if configured_model == "meta/muse-glimmer-30b":
            configured_model = DEFAULT_AI_MODEL
        self.model = configured_model

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
            lines.append("## Tareas Pendientes: Ninguna pendiente por ahora (el usuario aún no ha creado tareas).")

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
            for k in (
                "podrías agregar",
                "te sugiero crear",
                "nueva tarea",
                "podrías crear",
                "añadir una tarea",
                "crear tu primera",
                "micro-tarea",
            )
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
            timeout=45.0,
            max_retries=1,
        )

    def _invoke_completion(self, client: OpenAI, model_name: str, messages: list[dict[str, Any]]) -> str:
        completion = client.chat.completions.create(
            model=model_name,
            messages=messages,
            temperature=0.7,
            top_p=0.95,
            max_tokens=768,
            stream=False,
        )

        content_parts: list[str] = []
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

        return self._clean_reply("".join(content_parts))

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
                    "IMPORTANTE: Sé directo y conciso (máximo 2 párrafos cortos).\n\n"
                    f"{context_prompt}"
                ),
            }
        ]

        for item in dto.history[-6:]:
            if isinstance(item, AIChatMessageDTO) and item.content.strip():
                messages.append({"role": item.role, "content": item.content.strip()})

        messages.append({"role": "user", "content": dto.message.strip()})

        client = self._create_client()
        candidate_models = [self.model]
        for fallback in FALLBACK_AI_MODELS:
            if fallback not in candidate_models:
                candidate_models.append(fallback)

        last_exc: Exception | None = None
        for model_name in candidate_models:
            try:
                reply = self._invoke_completion(client, model_name, messages)
                if reply:
                    return AIChatResponseDTO(
                        reply=reply,
                        model=model_name,
                        actions=self._extract_actions(reply),
                    )
            except Exception as exc:
                last_exc = exc
                err_str = str(exc)
                # Si el error es 404/410 (modelo retirado) o respuesta vacía, intenta el siguiente modelo
                if any(code in err_str for code in ("404", "410", "Not Found", "Gone", "timed out")):
                    continue
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Error al comunicarse con el proveedor de IA: {exc}",
                ) from exc

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error al comunicarse con el proveedor de IA: {last_exc or 'sin respuesta'}",
        )
