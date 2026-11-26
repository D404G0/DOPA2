"""Punto de Entrada de la API RESTful — Proyecto DOPA (Gestión y Enfoque para TDAH).

Agente Responsable: 3.2. Agente de API y Lógica de Negocio (Backend Core Agent)
Arquitectura en 5 Capas (Presentación -> Transferencia -> Lógica de Negocio -> Acceso a Datos -> Dominio).
"""

from contextlib import asynccontextmanager
import os

from fastapi import Depends, FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.data.database import get_db, init_db_schema
from app.presentation.routers import (
    ai,
    auth,
    dashboard,
    financial_goals,
    gamification,
    personal_records,
    pomodoro,
    reminders,
    routines,
    tasks,
)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Inicializa y verifica el esquema de base de datos al arrancar el servidor."""
    if not os.getenv("PYTEST_CURRENT_TEST"):
        init_db_schema()
    yield


app = FastAPI(
    title="DOPA API — Gestión y Enfoque para TDAH",
    description=(
        "Backend RESTful en 5 capas para la aplicación móvil **DOPA** ('Vamos un paso a la vez', "
        "'Poquito a poquito'). Diseñado para reducir la sobrecarga cognitiva en personas con TDAH "
        "mediante micro-pasos, temporizador Pomodoro de enfoque suave y gamificación libre de culpa."
    ),
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_request: Request, exc: RequestValidationError) -> JSONResponse:
    """Manejador centralizado de errores de validación Pydantic con mensajes claros para el cliente móvil."""
    errores = []
    for err in exc.errors():
        campo = ".".join(str(loc) for loc in err.get("loc", []) if loc != "body")
        mensaje = err.get("msg", "Valor inválido")
        errores.append({"campo": campo or "payload", "mensaje": mensaje})

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "detail": "Error de validación en los datos enviados.",
            "errores": errores,
        },
    )


@app.get(
    "/health",
    tags=["0. Salud del Servicio"],
    summary="Verificar estado operativo del servidor DOPA y su conexión a la base de datos (RNF-10)",
)
def health_check(db: Session = Depends(get_db)) -> JSONResponse:
    """Endpoint de salud y disponibilidad del servicio + PostgreSQL."""
    try:
        db.execute(text("SELECT 1"))
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "status": "ok",
                "database": "ok",
                "service": "DOPA API — Gestión y Enfoque para TDAH",
                "version": "1.0.0",
                "architecture": "5-Layer Layered Architecture",
            },
        )
    except Exception as exc:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "error",
                "database": f"error: {exc}",
                "service": "DOPA API — Gestión y Enfoque para TDAH",
                "version": "1.0.0",
            },
        )


# Registro de routers versionados bajo /api/v1
app.include_router(auth.router)
app.include_router(dashboard.router)
app.include_router(tasks.router)
app.include_router(routines.router)
app.include_router(pomodoro.router)
app.include_router(reminders.router)
app.include_router(gamification.router)
app.include_router(personal_records.router)
app.include_router(financial_goals.router)
app.include_router(ai.router)
