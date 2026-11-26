# 🧠 DOPA — Gestión de Energía, Enfoque Suave y Bienestar Diario

**DOPA** es una aplicación multiplataforma (Android APK + Web/PWA + API RESTful en FastAPI + PostgreSQL 16 + Agente de IA con NVIDIA NIM) diseñada para personas con TDAH que buscan organizar su día sin estrés, con inicio completamente limpio y datos sincronizados en tiempo real.

---

## 📚 Documentación del Proyecto

1. 🔧 **[Arquitectura Técnica Completa (`docs/ARQUITECTURA_TECNICA_COMPLETA.md`)](docs/ARQUITECTURA_TECNICA_COMPLETA.md)**
   Explicación técnica detallada de toda la estructura del repositorio, backend en 5 capas, modelo PostgreSQL, agente de IA, persistencia híbrida en Flutter y topología Docker.
2. 📖 **[Informe General No Técnico (`docs/INFORME_GENERAL_NO_TECNICO.md`)](docs/INFORME_GENERAL_NO_TECNICO.md)**
   Explicación clara y accesible para cualquier persona sobre qué es DOPA, cómo funciona y qué mejoras incluye esta versión.
3. 🛠️ **[Instructivo de Instalación y Correcciones (`docs/INSTRUCTIVO_INSTALACION_Y_CORRECCIONES.md`)](docs/INSTRUCTIVO_INSTALACION_Y_CORRECCIONES.md)**
   Paso a paso completo para instalar el APK, levantar Docker con túnel público HTTPS, configurar `.env` y solucionar errores comunes.
4. 📡 **[Contrato de API REST (`docs/API_CONTRACT.md`)](docs/API_CONTRACT.md)**
   Especificación técnica de los endpoints `/api/v1/*`.
5. 📱 **APK listo para instalar:** [`apk/dopa-release.apk`](apk/dopa-release.apk)

---

## ⚡ Inicio Rápido: Docker + Internet + Android APK

### 1. Configurar variables de entorno
```bash
cp .env.example .env
# Asegúrate de incluir tu AI_API_KEY válida de NVIDIA NIM en .env
```

### 2. Levantar PostgreSQL + Backend FastAPI + Túnel HTTPS Público
```bash
docker compose --profile internet down -v
docker compose --profile internet up -d --build
```
- **API Backend (Swagger UI):** `http://localhost:8000/docs`
- **Health Check:** `http://localhost:8000/health`
- **Estado IA:** `http://localhost:8000/api/v1/ai/status`
- **PostgreSQL 16 en host:** puerto `5433` (`POSTGRES_PORT=5433`, volumen `postgres_data`, esquema 100% limpio sin datos precargados)
- **pgAdmin 4:** `http://localhost:5050` (`admin@dopa.app` / `admin123`)

### 3. Obtener URL pública para conectar el celular por Internet
```bash
docker logs dopa_internet_tunnel 2>&1 | grep trycloudflare.com
```
1. Instala [`apk/dopa-release.apk`](apk/dopa-release.apk) en tu celular Android.
2. Al abrir **DOPA**, escribe tu nombre real en la pantalla de bienvenida.
3. Toca **`• dopa`** (arriba a la derecha), pega la URL `https://<...>.trycloudflare.com`, presiona **«Probar y guardar servidor»** y luego crea tu cuenta o inicia sesión.

---

## 🧪 Ejecutar Pruebas

```bash
# Backend (PyTest)
docker compose run --rm --no-deps -v "$PWD/tests:/app/tests" backend pytest -q

# Frontend (Flutter)
flutter analyze --no-fatal-infos
flutter test
```
