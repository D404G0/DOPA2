# Instructivo de Instalación, Puesta en Marcha y Correcciones — DOPA

Guía práctica paso a paso para levantar el servidor Docker en tu computador, instalar el APK en Android, conectar el celular por Internet o Wi-Fi y resolver cualquier inconveniente técnico.

---

## 1. Diagnóstico de Problemas Corregidos

Si antes intentaste conectar tu celular mediante la URL y falló, estas fueron las causas reales detectadas y resueltas:

1. **Choque de puerto `5432` en PostgreSQL:** Muchas computadoras (especialmente Windows con PostgreSQL instalado localmente) ya usan el puerto `5432`. Al fallar el arranque o enlazar la base equivocada, `/api/v1/auth/login` o el registro devolvían `HTTP 500`.
   - **Solución:** El puerto externo en el computador pasó a **`5433`** (`POSTGRES_PORT=5433`), mientras que dentro de la red privada de Docker la API sigue hablando con `db:5432`.
2. **Esquema faltante si el volumen ya existía:** `init.sql` solo se ejecuta cuando el volumen `postgres_data` es virgen. Si existía un volumen previo vacío, faltaban tablas.
   - **Solución:** FastAPI ahora ejecuta `init_db_schema()` al arrancar (`lifespan`) creando automáticamente cualquier tabla ausente.
3. **Falsa detección de "Sin conexión" en el celular:** Si `/health` respondía bien (`200 OK`), la app intentaba un auto-login oculto demo que fallaba y apagaba la luz verde de conexión haciéndote creer que la URL estaba mal.
   - **Solución:** Ahora **`• dopa`** distingue 3 estados claros:
     - **Verde:** Docker conectado **y** cuenta PostgreSQL activa.
     - **Amarillo:** Docker conectado, pero falta **Crear cuenta** o **Iniciar sesión**.
     - **Naranja:** Modo local (sin conexión al servidor).
4. **Modelo de IA retirado:** El modelo anterior (`meta/muse-glimmer-30b`) devolvía error `HTTP 410 Gone` desde NVIDIA NIM.
   - **Solución:** Se actualizó a **`nvidia/nemotron-3.5-bolt-e4b`** (verificado con respuestas en ~1 segundo usando tu clave en `.env`).

---

## 2. Requisitos Previos en el Computador

1. **Docker Desktop** (Windows/macOS) o **Docker Engine + Compose** (Linux) abierto y en ejecución.
2. **Archivo `.env`** en la raíz del proyecto (NO se sube a GitHub por seguridad porque contiene claves privadas).

### Crear o verificar el archivo `.env`
Si descargaste o clonaste el repositorio y no ves el archivo `.env`, créalo copiando `.env.example`:

- **En Windows (PowerShell):**
  ```powershell
  Copy-Item .env.example .env
  notepad .env
  ```
- **En Linux / macOS:**
  ```bash
  cp .env.example .env
  nano .env
  ```

Verifica que dentro de `.env` tengas valores válidos, especialmente tu clave de NVIDIA NIM:
```env
POSTGRES_USER=dopa_user
POSTGRES_PASSWORD=dopa_secret_pass_2026
POSTGRES_DB=dopa_db
POSTGRES_PORT=5433

JWT_SECRET_KEY=cambia-esta-clave-secreta-por-una-larga-y-segura
AI_API_BASE_URL=https://integrate.api.nvidia.com/v1
AI_API_KEY=nvapi-TU_CLAVE_AQUI
AI_MODEL=nvidia/nemotron-3.5-bolt-e4b
```

---

## 3. Cómo Levantar Docker Limpio + Túnel HTTPS para Internet

> **Importante si ya habías levantado Docker antes con datos viejos:** ejecuta primero `down -v` para borrar el volumen anterior de base de datos y empezar 100% limpio sin datos de prueba antiguos.

```bash
# 1. Limpiar contenedores y volumen previo (empieza BD vacía y limpia)
docker compose --profile internet down -v

# 2. Construir y levantar Base de Datos + Backend + Túnel HTTPS público
docker compose --profile internet up -d --build
```

### Obtener la URL pública para tu celular (Internet 4G/5G o cualquier Wi-Fi)
Ejecuta:
```bash
docker logs dopa_internet_tunnel 2>&1 | grep trycloudflare.com
```
*(En PowerShell de Windows si `grep` no existe, usa: `docker logs dopa_internet_tunnel 2>&1 | Select-String "trycloudflare.com"`)*

Verás una línea parecida a:
```text
https://ejemplo-palabras-aleatorias.trycloudflare.com
```
Copia esa URL exactamente completa (empieza con `https://` y **sin** barras `/` al final).

> Nota: Los túneles rápidos gratuitos de Cloudflare (`trycloudflare.com`) generan una URL nueva cada vez que reinicias el contenedor `dopa_internet_tunnel`. Si apagas tu PC y la vuelves a encender otro día, consulta el nuevo enlace y pégalo en **`• dopa`**.

---

## 4. Cómo Instalar el APK y Conectarlo desde el Celular

1. Copia el archivo **`apk/dopa-release.apk`** del repositorio a tu teléfono Android y ábrelo para instalar (si Android pide permiso, habilita *"Instalar aplicaciones de orígenes desconocidos"* para tu gestor de archivos).
2. Al abrir **DOPA**:
   - Escribe **tu nombre** en *"¿Cómo te llamas?"*.
   - Puedes desplegar **"Conectar con Docker / Cuenta ahora"** ahí mismo **o** tocar **"Empezar ahora"** y configurarlo después arriba a la derecha en **`• dopa`**.
3. Para conectar con PostgreSQL en Docker:
   - Toca **`• dopa`** (esquina superior derecha en *Inicio*).
   - En el campo **2. Servidor Backend (Docker)** pega la URL `https://....trycloudflare.com` (o `http://<IP_LOCAL_DE_TU_PC>:8000` si usas el mismo Wi-Fi).
   - Toca **"Probar y guardar servidor"**. Debe salir un aviso verde: *"Servidor Docker conectado..."*.
   - Baja a **3. Cuenta PostgreSQL**, selecciona **"Crear cuenta"**, ingresa tu nombre, correo y una contraseña de mínimo **8 caracteres**, y toca **"Crear cuenta y sincronizar"**.
4. ¡Listo! Cada tarea, micro-paso, racha, sesión de enfoque y chat con la IA quedará guardado en la base de datos PostgreSQL de Docker.

---

## 5. Verificación Rápida de Que Todo Funciona

### A. Verificar desde el computador que el servidor y PostgreSQL están bien
Abre en tu navegador o ejecuta `curl`:
- Salud del servidor: `http://localhost:8000/health` → debe responder `{"status": "ok", "database": "ok", ...}`.
- Estado de la IA: `http://localhost:8000/api/v1/ai/status` → debe responder `"configured": true` y `"model": "nvidia/nemotron-3.5-bolt-e4b"`.
- Tablas reales en PostgreSQL:
  ```bash
  docker exec -it dopa_postgres_db psql -U dopa_user -d dopa_db -c "SELECT id, nombre, correo FROM usuario;"
  docker exec -it dopa_postgres_db psql -U dopa_user -d dopa_db -c "SELECT id, titulo, completada FROM tarea;"
  ```

### B. Ejecutar pruebas automatizadas
```bash
# Backend (dentro del contenedor o entorno Python virtual)
docker compose run --rm --no-deps -v "$PWD/tests:/app/tests" backend pytest -q

# Frontend Flutter
flutter analyze --no-fatal-infos
flutter test
```

---

## 6. Guía Rápida de Correcciones (Troubleshooting)

| Síntoma / Error | Causa Probable | Cómo Corregirlo |
| :--- | :--- | :--- |
| **`Error al probar el servidor` con URL `trycloudflare.com`** | El túnel aún estaba iniciando, se reinició Docker y cambió la URL, o pusiste la URL antigua en caché. | Ejecuta `docker logs dopa_internet_tunnel 2>&1 \| Select-String "trycloudflare.com"` (Windows) o `grep trycloudflare.com` (Linux/Mac) para obtener la URL activa actual. |
| **`No se pudo conectar` usando IP Wi-Fi `http://192.168.x.x:8000`** | El firewall de Windows bloquea el puerto `8000` o el celular está en datos móviles / otra subred. | Usa el túnel HTTPS (`--profile internet`) para evitar firewalls y redes locales, o permite TCP `8000` en el Firewall de Windows. |
| **El botón `• dopa` está Amarillo** | El servidor Docker SÍ respondió, pero no has iniciado sesión ni creado tu cuenta. | Abre `• dopa`, ve a la sección *3. Cuenta PostgreSQL*, crea tu cuenta o inicia sesión. |
| **`El servidor Docker aún no tiene configurada AI_API_KEY`** | Falta el archivo `.env` o `AI_API_KEY` quedó vacío al levantar Docker. | Verifica `.env`, asegúrate de tener `AI_API_KEY=nvapi-...` y reinicia el contenedor con `docker compose --profile internet up -d --build`. |
| **La IA responde lento o error `410`** | Se quedó un modelo obsoleto en `.env`. | Confirma en `.env` la línea `AI_MODEL=nvidia/nemotron-3.5-bolt-e4b` y recrea el backend. |
| **`Bind for 0.0.0.0:5432 failed`** | Ya existe otro PostgreSQL corriendo en la PC usando `5432`. | Mantén `POSTGRES_PORT=5433` (o `5434` si `5433` estuviera ocupado) en `.env` y `docker-compose.yml`. |
| **Error HTTP 422 al registrarse** | La contraseña tiene menos de 8 caracteres, el correo tiene formato inválido o el nombre tiene menos de 2 letras. | Usa una contraseña de al menos 8 caracteres y un correo válido (`usuario@dominio.com`). |
