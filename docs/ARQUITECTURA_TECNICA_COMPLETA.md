# Arquitectura Técnica Completa — Proyecto DOPA

Documento técnico exhaustivo de la arquitectura, estructura de código, modelo de datos, seguridad, comunicación cliente-servidor, agente de inteligencia artificial, infraestructura Docker y suite de pruebas del ecosistema **DOPA**.

---

## 1. Visión General y Stack Tecnológico

**DOPA** implementa una arquitectura distribuida cliente-servidor compuesta por tres subsistemas principales desacoplados:

| Capa / Subsistema | Tecnología Principal | Rol Técnico |
| :--- | :--- | :--- |
| **Cliente Móvil / Web** | Flutter 3.x (Dart), `http`, `shared_preferences` | Interfaz neuro-inclusiva (*Soft Neo-Brutalism*), onboarding personalizado, persistencia local híbrida offline-first y sincronización REST. |
| **API Backend** | FastAPI (Python 3.12), Pydantic v2, Uvicorn | API RESTful stateless bajo arquitectura limpia de 5 capas (`/api/v1/*`), autenticación JWT, idempotencia y orquestación de IA. |
| **Base de Datos** | PostgreSQL 16 (`psycopg3` + SQLAlchemy 2.x ORM) | Persistencia relacional transaccional de usuarios, preferencias, tareas, micro-pasos, sesiones Pomodoro, rutinas, gamificación y registros personales. |
| **Agente de IA** | SDK oficial `openai` apuntando a NVIDIA NIM (`nvidia/nemotron-3.5-bolt-e4b`) | Asistente contextual que consulta los datos reales del usuario en PostgreSQL y genera recomendaciones accionables en español. |
| **Orquestación & Red** | Docker Compose + Cloudflare Tunnel (`cloudflared`) | Aislamiento de contenedores (`db`, `backend`, `pgadmin`, `frontend_web`, `tunnel`) y exposición segura HTTPS hacia Internet sin abrir puertos del router. |

---

## 2. Estructura Completa del Repositorio

```text
DOPA2/
├── .env / .env.example                 # Variables de entorno (POSTGRES_PORT=5433, AI_API_KEY, AI_MODEL, JWT_SECRET_KEY)
├── docker-compose.yml                  # Orquestación multi-servicio (db, backend, pgadmin, frontend_web, tunnel)
├── Dockerfile                          # Imagen de producción Python 3.12-slim para FastAPI
├── Dockerfile.web                      # Imagen Nginx para despliegue Web/PWA
├── pubspec.yaml                        # Dependencias Flutter (http, shared_preferences) y assets/icon/dopa_logo.png
├── requirements.txt                    # Dependencias Python (fastapi, sqlalchemy, pydantic, pyjwt, bcrypt, openai, pytest)
│
├── assets/icon/dopa_logo.png           # Logotipo vectorial rasterizado de DOPA (512x512)
├── android/app/src/main/res/mipmap-*/  # Íconos de lanzador Android (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
├── web/                                # Íconos PWA y favicon personalizados
│
├── database/
│   ├── init.sql                        # DDL puro en PostgreSQL 16 (3 enums + 10 tablas + índices; sin datos demo)
│   └── ER_DIAGRAM.md                   # Diagrama entidad-relación
│
├── app/                                # BACKEND FASTAPI — ARQUITECTURA LIMPIA EN 5 CAPAS
│   ├── main.py                         # Lifecycle (lifespan -> init_db_schema), CORS, RateLimitMiddleware, GET /health
│   ├── presentation/                   # Capa 1: Presentación (Routers REST + Dependencias JWT)
│   │   ├── dependencies.py             # get_current_user (Bearer JWT) y validación de token revocado
│   │   └── routers/
│   │       ├── auth.py                 # /api/v1/auth (register, login, refresh, logout, me, PUT profile, preferences)
│   │       ├── dashboard.py            # /api/v1/dashboard (resumen diario, energy-checkin, quick-task)
│   │       ├── tasks.py                # /api/v1/tasks (CRUD tareas, completado idempotente, CRUD /subtasks)
│   │       ├── routines.py             # /api/v1/routines (rutinas libres de culpa y resumen amable)
│   │       ├── pomodoro.py             # /api/v1/pomodoro (sesiones de enfoque suave y actividades de descanso)
│   │       ├── reminders.py            # /api/v1/reminders (recordatorios)
│   │       ├── gamification.py         # /api/v1/gamification (summary con rachas reales y actividad_semanal, rewards)
│   │       ├── personal_records.py     # /api/v1/personal-records (diario de energía y bienestar)
│   │       ├── financial_goals.py      # /api/v1/financial-goals (metas personales cuantitativas)
│   │       └── ai.py                   # /api/v1/ai (/status público y /chat autenticado con contexto PostgreSQL)
│   ├── core/                           # Capa 2: Lógica de Negocio, Seguridad e IA
│   │   ├── services.py                 # AuthService, DashboardService, TaskService, RoutineService, PomodoroService, GamificationService, etc.
│   │   ├── ai_service.py               # DopaAIService (OpenAI SDK -> NVIDIA NIM, fallback de modelos, limpieza <think>)
│   │   ├── security.py                 # Hash bcrypt, JWT Access/Refresh, revocación, RateLimitMiddleware, SecurityHeaders
│   │   └── interfaces.py               # Protocolos abstractos de repositorios
│   ├── transfer/                       # Capa 3: Transferencia y Serialización
│   │   ├── dtos.py                     # Esquemas Pydantic v2 RequestDTO / ResponseDTO (validación estricta)
│   │   └── mappers.py                  # Mapeadores ORM <-> DTO (cálculos derivados de progreso y esfuerzo)
│   ├── domain/                         # Capa 4: Entidades y Enumeraciones de Dominio
│   │   └── models.py                   # Clases ORM SQLAlchemy y Enums (Usuario, Tarea, Subtarea, SesionPomodoro, etc.)
│   └── data/                           # Capa 5: Acceso a Datos y Conexión
│       ├── database.py                 # Engine PostgreSQL/SQLite, SessionLocal, get_db, init_db_schema()
│       └── repositories.py             # Patrón Repository (UsuarioRepository, TareaRepository, SubtareaRepository, etc.)
│
├── lib/                                # FRONTEND FLUTTER
│   ├── main.dart                       # Inicialización de ApiService + DBService y enrutamiento reactivo Onboarding vs App
│   ├── theme/app_theme.dart            # Sistema de diseño Soft Neo-Brutalism (paleta pastel y bordes 1.8dp)
│   ├── models/                         # Modelos Dart + deserialización backend y mapa local
│   │   ├── user_model.dart             # Usuario (valores iniciales en 0, sin datos demo)
│   │   ├── task_model.dart             # TareaBloque, MicroPaso, EstadoTarea
│   │   ├── focus_session_model.dart    # SesionEnfoque
│   │   ├── wellness_record_model.dart  # RegistroBienestar, TipoHumor
│   │   ├── reward_model.dart           # Recompensa
│   │   └── ai_chat_model.dart          # ChatMessage, AIAction
│   ├── services/                       # Capa de Comunicación y Persistencia Híbrida
│   │   ├── api_service.dart            # Cliente HTTP singleton, JWT, testAndSaveServer(), cabeceras ngrok/túnel, timeouts
│   │   ├── db_service.dart             # Caché reactiva (ValueNotifier), SharedPreferences, syncLocalDataToServer()
│   │   ├── ai_chat_service.dart        # Orquestación chat IA (vía /api/v1/ai/chat)
│   │   └── ai_context_service.dart     # Captura de sección activa para contexto de IA
│   ├── screens/                        # Pantallas de la aplicación
│   │   ├── onboarding_screen.dart      # Bienvenida: solicita nombre real + conexión Docker opcional
│   │   ├── main_navigation_screen.dart # Contenedor con IndexedStack (4 pestañas) + botón flotante IA
│   │   ├── home_dashboard_screen.dart  # Tab Inicio: saludo personalizado, energía, quick-task y botón "• dopa"
│   │   ├── tasks_screen.dart           # Tab Tareas: lista de micro-tareas, filtros y creación/edición
│   │   ├── soft_focus_screen.dart      # Temporizador de enfoque suave y lista interactiva de micro-pasos
│   │   ├── session_success_screen.dart # Celebración sin culpa al completar enfoque/tarea
│   │   ├── dopamine_stats_screen.dart  # Tab Dopamina: puntos reales, nivel, humor y gráfico semanal real
│   │   └── gentle_break_screen.dart    # Tab Pausa: temporizador de descanso y actividades de bajo estímulo
│   └── widgets/                        # Componentes reutilizables
│       ├── server_settings_sheet.dart  # Modal de perfil (nombre), URL Docker/túnel y cuenta PostgreSQL
│       ├── ai_assistant_panel.dart     # Panel modal del chat con el agente de IA
│       ├── streak_chart.dart           # Gráfico de barras semanales L-D dinámico (weeklyActivity)
│       ├── energy_bar.dart             # Selector de nivel de energía diaria
│       ├── mood_selector.dart          # Registro de humor
│       ├── task_editor_sheet.dart      # Modal CRUD para crear/editar tareas y micro-pasos
│       ├── task_item_tile.dart         # Tarjeta expandible de micro-tarea
│       ├── ai_recommendation_card.dart # Tarjeta de recomendación contextual adaptativa
│       ├── ai_floating_button.dart     # Botón flotante de acceso al asistente IA
│       ├── ai_chat_bubble.dart         # Burbujas y botones de acción rápida en chat IA
│       ├── dopa_card.dart              # Contenedor Soft Neo-Brutalism
│       └── bottom_nav_bar.dart         # Barra inferior de 4 destinos
│
├── tests/                              # Suite PyTest del Backend (31 pruebas)
│   ├── conftest.py                     # SQLite en memoria aislado por prueba + fixtures
│   ├── test_api_endpoints.py           # Pruebas de integración de los 9 módulos
│   ├── test_ai_endpoint.py             # Pruebas unitarias/contrato de /api/v1/ai/status y /api/v1/ai/chat
│   ├── test_e2e_user_flows.py          # Flujos completos registro -> tarea -> pomodoro -> gamificación
│   ├── test_security_and_perf.py       # Aislamiento multiusuario (IDOR), JWT revocado, idempotencia, latencia
│   └── test_unit_services_and_mappers.py # Pruebas unitarias de mappers y servicios
│
└── test/widget_test.dart               # Suite Flutter (4 pruebas: Onboarding, estado en cero, CRUD y MockClient REST)
```

---

## 3. Arquitectura del Backend (FastAPI — 5 Capas)

Cada solicitud HTTP entrante atraviesa exactamente cinco capas unidireccionales:

1. **Capa de Presentación (`app/presentation/`)**
   - `app/main.py` registra los routers bajo el prefijo `/api/v1` y expone `GET /health` ejecutando `SELECT 1` sobre PostgreSQL mediante `Depends(get_db)`.
   - Al arrancar el servidor, el gestor `@asynccontextmanager lifespan` ejecuta `init_db_schema()`, creando automáticamente cualquier tabla faltante con `Base.metadata.create_all(bind=engine, checkfirst=True)` y tolerancia a reintentos si Postgres tarda en iniciar.
   - `RateLimitMiddleware` protege los endpoints aplicando ventana deslizante por IP/ruta.
   - `dependencies.py` extrae el JWT `Bearer`, verifica firma HS256, fecha de expiración y comprueba en `token_revocado` que no haya sido cerrado por `/logout`.

2. **Capa Core / Servicios (`app/core/`)**
   - `AuthService`: Registro con hashing `bcrypt` (cost factor seguro), inicio de sesión, renovación mediante `refresh_token`, actualización de nombre (`PUT /api/v1/auth/profile`) y preferencias (`PUT /api/v1/auth/preferences`).
   - `TaskService`: CRUD completo de tareas y subtareas verificando propiedad (`id_usuario == current_user.id`) para impedir ataques IDOR. En `POST /api/v1/tasks/{id}/complete`, usa la tabla `clave_idempotencia` con la cabecera `Idempotency-Key` para garantizar que reintentos por red móvil inestable no dupliquen puntos de dopamina.
   - `GamificationService.get_summary()`: Calcula los puntos reales, nivel (`(puntos // 50) + 1`), tareas completadas totales, sesiones Pomodoro completadas, **días activos registrados** reales (contando fechas distintas de actividad en `registro_gamificacion` / tareas completadas / sesiones) y un arreglo booleano `actividad_semanal` de 7 posiciones (`[L, M, X, J, V, S, D]` de la semana ISO actual). Si el usuario es nuevo (`puntos == 0`, `tareas == 0`, `pomodoros == 0`), devuelve exactamente `0` y `[False]*7`.
   - `DashboardService`: Genera saludo dinámico usando el primer nombre real del usuario (`¡Hola, <Nombre>!`), estado de energía más reciente desde `registropersonal`, conteo de pendientes reales y hasta 3 micro-tareas activas.

3. **Capa de Transferencia (`app/transfer/`)**
   - Pydantic v2 valida estrictamente entradas (`RegisterRequestDTO` exige contraseña ≥ 8 caracteres y correo válido; `UserProfileUpdateRequestDTO` exige nombre válido ≥ 2 caracteres).
   - `mappers.py` transforma entidades ORM en DTOs optimizados calculando etiquetas de bajo estímulo (`Fácil`, `Suave`, `Sin prisa`) y porcentajes de avance de subtareas.

4. **Capa de Dominio y Datos (`app/domain/`, `app/data/`)**
   - SQLAlchemy 2.x define 10 entidades mapeadas directamente al esquema definido en `database/init.sql`:
     - `usuario`, `preferencias_usuario`, `tarea`, `subtarea`, `rutina`, `sesion_pomodoro`, `recordatorio`, `registro_gamificacion`, `recompensa`, `registropersonal`, `metafinanciera`, más tablas operativas `token_revocado` y `clave_idempotencia`.
   - Todos los repositorios en `repositories.py` encapsulan consultas parametrizadas previniendo inyección SQL.

---

## 4. Agente de Inteligencia Artificial (`app/core/ai_service.py`)

El módulo de IA no funciona con respuestas genéricas desconectadas:

1. El cliente Flutter llama a `POST /api/v1/ai/chat` adjuntando su JWT, su pregunta actual, historial reciente (máximo 10 mensajes) y la pestaña desde donde pregunta (`section`).
2. `app/presentation/routers/ai.py` recupera de PostgreSQL el contexto vivo del usuario autenticado: nombre real, puntos de dopamina, nivel, lista real de tareas pendientes/completadas con sus micro-pasos y registros recientes de energía/humor.
3. `DopaAIService` inyecta dicho contexto en el mensaje `system` usando el SDK oficial `from openai import OpenAI` apuntando a `https://integrate.api.nvidia.com/v1` con modelo principal **`nvidia/nemotron-3.5-bolt-e4b`** (y respaldo automático a `minimaxai/minimax-m3.1-flash` si el modelo principal falla temporalmente). Si `.env` conservaba el modelo retirado `meta/muse-glimmer-30b` (HTTP 410 Gone en NVIDIA NIM), el servicio lo migra automáticamente en memoria a `nvidia/nemotron-3.5-bolt-e4b`.
4. La respuesta filtra etiquetas internas de razonamiento (`<think>...</think>`) y añade acciones rápidas estructuradas (`AIActionDTO`, ej. abrir una micro-tarea o iniciar enfoque).
5. `GET /api/v1/ai/status` permite verificar públicamente sin token si `AI_API_KEY` está configurada y qué modelo está activo.

---

## 5. Arquitectura del Frontend (Flutter) y Persistencia Híbrida

### 5.1 Flujo de Arranque y Estado Limpio
1. `main()` ejecuta en orden estricto:
   - `ApiService.instance.initFromStorage()`: restaura URL del servidor Docker y tokens JWT guardados en `SharedPreferences`.
   - `DBService.instance.initLocalState()`: restaura nombre personalizado del usuario (`dopa_user_name`), tareas locales (`dopa_local_tasks`), puntos, sesiones completadas, energía y arreglo semanal (`[false]*7` por defecto).
2. `DopaApp` escucha reactivamente `DBService.instance.profileReadyNotifier`:
   - Si no existe nombre ni sesión autenticada, muestra `OnboardingScreen`.
   - Una vez configurado el nombre (y opcionalmente cuenta Docker), transiciona a `MainNavigationScreen`.

### 5.2 Separación Crítica entre Alcance del Servidor y Sesión
Anteriormente, el frontend mezclaba fallas de autenticación (`HTTP 401`) con fallas de red y ejecutaba un auto-login oculto con credenciales demo (`fred@dopa.app`). En la arquitectura actual:
- `ApiService.connectionStatusNotifier` representa exclusivamente si el servidor Docker respondió al endpoint `/health` o devolvió un HTTP `< 500`.
- `ApiService.authStatusNotifier` representa exclusivamente si existe un JWT de usuario válido.
- `ApiService.testAndSaveServer(url)` normaliza la URL (añadiendo esquema si falta y `/api/v1`), la persiste en `SharedPreferences` y ejecuta `GET /health` reportando diagnósticos precisos (`lastHealthError`).
- Cuando un usuario crea tareas offline/localmente antes de conectar Docker y luego inicia sesión o crea su cuenta en `ServerSettingsSheet`, `DBService.syncLocalDataToServer()` sube automáticamente las tareas locales pendientes (`_unsyncedLocalTaskIds`) hacia `POST /api/v1/tasks` en PostgreSQL antes de refrescar la vista desde la base de datos.

---

## 6. Topología Docker y Red (`docker-compose.yml`)

| Servicio / Contenedor | Puerto Host → Contenedor | Función |
| :--- | :--- | :--- |
| `db` (`dopa_postgres_db`) | `5433` → `5432` (configurable vía `POSTGRES_PORT`) | PostgreSQL 16 con esquema limpio `database/init.sql` y volumen `postgres_data`. Usar `5433` en host evita conflictos con instalaciones locales de PostgreSQL en Windows/Linux. |
| `backend` (`dopa_fastapi_backend`) | `8000` → `8000` | API FastAPI conectada a `db:5432` en la red interna `dopa_network`. Carga `.env`. |
| `pgadmin` (`dopa_pgadmin`) | `5050` → `80` (perfil `tools` o por defecto) | Administración visual de la base de datos. |
| `tunnel` (`dopa_internet_tunnel`) | Túnel saliente HTTPS (perfil `internet`) | `cloudflared tunnel --url http://backend:8000` para conectar celulares con datos móviles 4G/5G sin abrir puertos en el router. |
| `frontend_web` (`dopa_web_app`) | `8080` → `80` (perfil `web`) | Compilación Nginx de Flutter Web. |
