# Informe General del Proyecto DOPA

*Documento explicativo en lenguaje claro para cualquier persona (sin necesidad de conocimientos técnicos).*

---

## 1. ¿Qué es DOPA?

**DOPA** es una aplicación móvil pensada para ayudar a las personas a organizar sus actividades diarias **sin estrés, sin culpa y paso a paso**, especialmente útil para quienes tienen **TDAH** o días en los que empezar una tarea grande resulta abrumador.

En lugar de mostrar listas infinitas llenas de pendientes urgentes y penalizaciones por días perdidos, DOPA propone una dinámica amigable:

- **Parte completamente en blanco:** Cuando instalas la aplicación por primera vez, no hay tareas inventadas, ni puntos falsos, ni rachas precargadas, ni el nombre de otra persona.
- **Lleva tu nombre real:** Lo primero que hace la aplicación al abrirse es preguntarte cómo te llamas para saludarte por tu nombre y personalizar la experiencia. Además, puedes cambiar tu nombre cuando quieras desde el menú de perfil.
- **Divide lo grande en micro-pasos:** Cualquier actividad que te cueste trabajo se puede dividir en pasos muy pequeños y manejables (por ejemplo, *"Abrir el cuaderno"* y *"Leer 1 párrafo"*).
- **Mide tu energía real:** Puedes indicar cómo te sientes hoy y recibir sugerencias acordes a tu nivel de energía.
- **Asistente de Inteligencia Artificial integrado:** Un acompañante amable dentro de la app que conoce las tareas reales que tú has creado y te sugiere cómo arrancar sin agobios.

---

## 2. ¿Cómo funciona la aplicación en el celular?

La app está organizada en **4 secciones simples** en la barra inferior y un **botón de asistente IA**:

1. **Inicio:** Muestra tu saludo personalizado (*"¡Hola, [Tu Nombre]!"*), tu medidor de energía del día, dos botones grandes para actuar rápido (**"¡Hacer algo fácil!"** o **"¡Tomar un break!"**) y tu próxima micro-tarea pendiente.
2. **Tareas (*Poquito a poquito*):** Aquí creas, editas o eliminas tus propias tareas y sus micro-pasos. Al tocar cualquier tarea puedes entrar al modo **Enfoque suave** (un temporizador corto sin presión) para concentrarte en un solo bloque.
3. **Dopamina (*Mi Dopamina hoy*):** Empieza en **0 puntos** y **0 días de racha**. A medida que terminas tus propias tareas o completas sesiones de enfoque, suma puntos reales, registra tu estado de ánimo y muestra qué días de la semana estuviste activo.
4. **Pausa (*Un break suave*):** Ofrece un espacio tranquilo de descanso y actividades cortas de bajo estímulo para recuperar energía sin sentir culpa.
5. **Asistente de IA:** Un botón siempre disponible para pedir ayuda cuando estás bloqueado, pedir que divida una tarea difícil o preguntar por dónde empezar.

---

## 3. ¿Dónde se guarda la información?

DOPA funciona en dos modos que se complementan automáticamente:

- **En tu propio celular (modo local):** Desde el primer segundo puedes escribir tu nombre y crear tus tareas incluso si todavía no has conectado el servidor. Todo queda guardado dentro del teléfono para que no pierdas nada.
- **En tu servidor Docker con Base de Datos PostgreSQL (modo en la nube propia / Internet):** Al tocar el botón superior derecho **`• dopa`**, puedes escribir la dirección de tu servidor (ya sea por Wi-Fi en casa o mediante una dirección HTTPS pública para conectarte desde cualquier lugar con datos móviles). Al crear tu cuenta o iniciar sesión allí:
  - Si ya habías creado tareas en el celular, **se suben automáticamente a la base de datos**.
  - A partir de ese momento, todas tus tareas, puntos, micro-pasos, sesiones, perfil e historial del asistente de IA quedan almacenados de forma permanente en la base de datos PostgreSQL dentro de Docker.

---

## 4. ¿Cómo está funcionando la Inteligencia Artificial?

El asistente de IA utiliza un servicio externo real (conectado de forma segura a través de tu propio servidor Docker, nunca exponiendo claves dentro del celular). Antes de responderte, lee tu nombre, tus puntos y tus tareas reales en la base de datos para darte consejos concretos sobre *tus* actividades reales, con un tono empático y conciso.

---

## 5. Resumen de mejoras realizadas en esta versión

| Qué ocurría antes | Qué hace ahora en esta versión |
| :--- | :--- |
| Aparecían tareas de ejemplo (*"Hacer la cama"*, *"Responder a Ana"*), puntos inventados y el nombre fijo *"Fred"*. | Empieza **100% nueva y vacía** (`0` tareas, `0 pts`, `0 días`). Cada persona escribe su propio nombre. |
| Al poner la URL del servidor en el celular fallaba porque faltaban tablas al arrancar desde cero, había choque del puerto `5432` en la PC y la app intentaba entrar en secreto con una cuenta demo. | El servidor crea las tablas automáticamente al iniciar, usa el puerto `5433` para evitar choques en la PC, y la app separa claramente *"Servidor conectado"* de *"Crear tu cuenta / Iniciar sesión"*. |
| El modelo anterior de IA estaba dado de baja por el proveedor (error `410`). | Actualizado a un modelo activo y rápido (`nvidia/nemotron-3.5-bolt-e4b`) verificado funcionando en tiempo real con respuestas en ~1 segundo. |
| El ícono de la app era el genérico de Flutter. | Cuenta con logotipo propio de **DOPA** en el ícono de Android, Web y encabezado de la app. |
