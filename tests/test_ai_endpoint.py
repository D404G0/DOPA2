"""Pruebas del módulo de Asistente de IA (`/api/v1/ai`) usando `from openai import OpenAI`."""

from types import SimpleNamespace


def test_ai_status_and_chat_endpoint(client, registered_user, monkeypatch):
    auth_headers = registered_user["headers"]
    # 1. Crear una tarea real para verificar que el contexto de BD se envía a OpenAI
    create_resp = client.post(
        "/api/v1/tasks",
        headers=auth_headers,
        json={
            "titulo": "Revisar apuntes de redes",
            "prioridad": "Baja",
            "subtareas": ["Abrir cuaderno", "Leer 2 páginas"],
        },
    )
    assert create_resp.status_code == 201

    # 2. Configurar variables de entorno y mockear el cliente OpenAI
    monkeypatch.setenv("AI_API_BASE_URL", "https://integrate.api.nvidia.com/v1")
    monkeypatch.setenv("AI_API_KEY", "nvapi-test-key")
    monkeypatch.setenv("AI_MODEL", "meta/muse-glimmer-30b")

    status_resp = client.get("/api/v1/ai/status")
    assert status_resp.status_code == 200
    status_data = status_resp.json()
    assert status_data["configured"] is True
    assert status_data["model"] == "meta/muse-glimmer-30b"

    captured_kwargs = {}

    class DummyCompletions:
        def create(self, **kwargs):
            captured_kwargs.update(kwargs)
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(
                            content='Te recomiendo empezar por "Revisar apuntes de redes" porque es fácil y luego tomar un break suave. 🌿'
                        )
                    )
                ]
            )

    class DummyOpenAI:
        def __init__(self, base_url=None, api_key=None, **kwargs):
            captured_kwargs["base_url"] = base_url
            captured_kwargs["api_key"] = api_key
            self.chat = SimpleNamespace(completions=DummyCompletions())

    monkeypatch.setattr("app.core.ai_service.OpenAI", DummyOpenAI)

    chat_resp = client.post(
        "/api/v1/ai/chat",
        headers=auth_headers,
        json={
            "message": "¿Qué debería hacer primero hoy?",
            "history": [],
            "section": "Tareas",
        },
    )
    assert chat_resp.status_code == 200
    data = chat_resp.json()
    assert "Revisar apuntes de redes" in data["reply"]
    assert data["model"] == "meta/muse-glimmer-30b"
    assert any(a["type"] == "tomarBreak" for a in data["actions"])

    # Verificar que se usó base_url, api_key y se incluyó la tarea real de la BD en el system prompt
    assert captured_kwargs["base_url"] == "https://integrate.api.nvidia.com/v1"
    assert captured_kwargs["api_key"] == "nvapi-test-key"
    system_prompt = captured_kwargs["messages"][0]["content"]
    assert "Revisar apuntes de redes" in system_prompt
    assert "Abrir cuaderno" in system_prompt
