# 🧠 DOPA — Gestión de Energía, Enfoque Suave y Bienestar Diario

**DOPA** es una plataforma integral (Móvil Android/iOS + Web/PWA + API RESTful en FastAPI + PostgreSQL 16) diseñada para personas con TDAH y perfiles neurodivergentes que buscan gestionar sus tareas diarias según su nivel de energía, dividirlas en micro-pasos, mantener sesiones de enfoque suave (*Soft Focus* / Pomodoro) y celebrar su progreso mediante gamificación libre de culpa.

---

## 📚 Documentación Principal del Proyecto

1. 🏗️ **[Estructura del Proyecto (`ESTRUCTURA_DEL_PROYECTO.md`)](ESTRUCTURA_DEL_PROYECTO.md)**
   Árbol de directorios unificado, arquitectura por capas del Frontend (Flutter) y Backend (FastAPI), modelo de base de datos PostgreSQL (10 tablas) y flujos de integración.
2. 🚀 **[Guía de Inicio, Ejecución Móvil y Despliegue (`GUIA_INICIO_Y_DESPLIEGUE.md`)](GUIA_INICIO_Y_DESPLIEGUE.md)**
   Instrucciones paso a paso para levantar el proyecto en local, ejecución móvil y despliegue.
3. 📡 **[Contrato de API REST (`docs/API_CONTRACT.md`)](docs/API_CONTRACT.md)**
   Especificación de los endpoints `/api/v1/*`, payloads JSON y códigos de respuesta.
4. 🤖 **[Configuración del Equipo de Agentes SDLC (`AGENTS.md`)](AGENTS.md)**
   Definición de los agentes del ciclo de desarrollo.

---

## ⚡ Inicio Rápido: Docker + App Android (APK)

### 1. Levantar Base de Datos PostgreSQL + Backend FastAPI (con Asistente IA) en Docker
```bash
cp .env.example .env
# Edita .env y coloca tu AI_API_KEY (NVIDIA NIM / OpenAI)
docker compose up -d --build
```
- **API Backend (Swagger UI):** `http://localhost:8000/docs`
- **Asistente IA (OpenAI SDK / NVIDIA NIM):** `POST /api/v1/ai/chat` y `GET /api/v1/ai/status`
- **Health Check:** `http://localhost:8000/health`
- **PostgreSQL 16:** puerto `5432` (volumen persistente `postgres_data`)
- **pgAdmin 4:** `http://localhost:5050` (`admin@dopa.app` / `admin123`)
- **Credenciales Demo:** `fred@dopa.app` / `Dopa1234!` (también puedes crear tu propia cuenta desde la app)

> Si además deseas levantar la versión Web/PWA en el puerto `8080`:
> ```bash
> docker compose --profile web up -d --build
> ```

### 2. Conectar la App Android (APK) desde **Internet (datos móviles 4G/5G o cualquier Wi-Fi)**
Si quieres que tu celular guarde los datos en tu Docker desde cualquier lugar por Internet (sin abrir puertos del router):
```bash
docker compose --profile internet up -d --build
docker logs dopa_internet_tunnel 2>&1 | grep trycloudflare.com
```
1. Copia la URL pública `https://<algo>.trycloudflare.com` que aparece en la consola.
2. En tu celular abre **DOPA**, toca **`• dopa`** (arriba a la derecha), pega esa URL HTTPS y presiona **«Probar y guardar servidor»**.
3. Inicia sesión o crea tu cuenta: toda la información se guardará por HTTPS en tu base de datos PostgreSQL de Docker.

### 3. Conectar la App Android (APK) en la misma red Wi-Fi local
1. Instala el APK generado (`build/app/outputs/flutter-apk/app-release.apk`) en tu celular Android.
2. Verifica la IP local de tu PC donde corre Docker (`ipconfig` en Windows o `hostname -I` en Linux/macOS, ej. `192.168.1.25`) y permite el puerto TCP `8000` en el firewall.
3. Abre **DOPA**, toca **`• dopa`** (arriba a la derecha en *Inicio*), ingresa `http://<IP_DE_TU_PC>:8000` y presiona **«Probar y guardar servidor»**.

### 3. Compilar el APK manualmente (opcional)
```bash
flutter pub get
flutter build apk --release
# O preconfigurando una IP fija por defecto:
flutter build apk --release --dart-define=API_BASE_URL=http://<IP_DE_TU_PC>:8000/api/v1
```

### 4. Ejecutar Suite de Pruebas (Testing)
```bash
# Backend (PyTest)
pytest -v

# Frontend (Análisis estático + Widget/API Tests)
flutter analyze
flutter test
```
