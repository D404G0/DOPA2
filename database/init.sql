-- =============================================================================
-- PROYECTO DOPA (Aplicación de Apoyo para Personas con TDAH)
-- Motor: PostgreSQL 16+
-- Esquema limpio: sin datos semilla ni tareas/rachas preestablecidas.
-- Cada usuario crea su cuenta, su perfil y sus propias tareas desde la app.
-- =============================================================================

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

-- -----------------------------------------------------------------------------
-- 1. TIPOS ENUM PERSONALIZADOS
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'prioridad_tarea') THEN
        CREATE TYPE prioridad_tarea AS ENUM ('Alta', 'Media', 'Baja');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_recordatorio') THEN
        CREATE TYPE tipo_recordatorio AS ENUM ('Tarea', 'Rutina', 'Compromiso');
    END IF;
END$$;

-- -----------------------------------------------------------------------------
-- 2. DEFINICIÓN DE LAS 10 TABLAS DEL ESQUEMA RELACIONAL
-- -----------------------------------------------------------------------------

-- 2.1. Tabla: usuario
CREATE TABLE IF NOT EXISTS usuario (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    correo VARCHAR(150) UNIQUE NOT NULL,
    contrasenahash VARCHAR(255) NOT NULL,
    puntos INT4 NOT NULL DEFAULT 0 CHECK (puntos >= 0),
    nivel INT4 NOT NULL DEFAULT 1 CHECK (nivel >= 1)
);

-- 2.2. Tabla: rutina
CREATE TABLE IF NOT EXISTS rutina (
    id SERIAL PRIMARY KEY,
    id_usuario INT4 NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    nombre VARCHAR(150) NOT NULL,
    recurrencia VARCHAR(100) NOT NULL,
    hora TIME NOT NULL,
    completadahoy BOOL NOT NULL DEFAULT FALSE
);

-- 2.3. Tabla: tarea
CREATE TABLE IF NOT EXISTS tarea (
    id SERIAL PRIMARY KEY,
    id_usuario INT4 NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    id_rutina INT4 NULL REFERENCES rutina(id) ON DELETE SET NULL,
    titulo VARCHAR(200) NOT NULL,
    descripcion TEXT,
    prioridad prioridad_tarea NOT NULL DEFAULT 'Media',
    fechavencimiento DATE,
    completada BOOL NOT NULL DEFAULT FALSE
);

-- 2.4. Tabla: subtarea (Micro-pasos para reducir la parálisis por análisis - HU-03)
CREATE TABLE IF NOT EXISTS subtarea (
    id SERIAL PRIMARY KEY,
    id_tarea INT4 NOT NULL REFERENCES tarea(id) ON DELETE CASCADE,
    descripcion VARCHAR(255) NOT NULL,
    completada BOOL NOT NULL DEFAULT FALSE
);

-- 2.5. Tabla: sesionpomodoro (Enfoque suave y pausas guiadas - HU-06)
CREATE TABLE IF NOT EXISTS sesionpomodoro (
    id SERIAL PRIMARY KEY,
    id_usuario INT4 NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    id_tarea INT4 NULL REFERENCES tarea(id) ON DELETE SET NULL,
    duracionconcentracion INT4 NOT NULL CHECK (duracionconcentracion > 0),
    duraciondescanso INT4 NOT NULL CHECK (duraciondescanso >= 0),
    sesionescompletadas INT4 NOT NULL DEFAULT 0 CHECK (sesionescompletadas >= 0)
);

-- 2.6. Tabla: recordatorio (Alertas de tareas, rutinas y compromisos - HU-05)
CREATE TABLE IF NOT EXISTS recordatorio (
    id SERIAL PRIMARY KEY,
    id_usuario INT4 NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    id_tarea INT4 NULL REFERENCES tarea(id) ON DELETE CASCADE,
    fechahora TIMESTAMP NOT NULL,
    mensaje VARCHAR(255) NOT NULL,
    tipo tipo_recordatorio NOT NULL DEFAULT 'Tarea',
    completadahoy BOOL NOT NULL DEFAULT FALSE
);

-- 2.7. Tabla: recompensa (Gamificación de dopamina libre de culpa - HU-07)
CREATE TABLE IF NOT EXISTS recompensa (
    id SERIAL PRIMARY KEY,
    id_tarea INT4 NULL REFERENCES tarea(id) ON DELETE SET NULL,
    nombre VARCHAR(150) NOT NULL,
    costopuntos INT4 NOT NULL DEFAULT 10 CHECK (costopuntos >= 0),
    desbloqueada BOOL NOT NULL DEFAULT FALSE
);

-- 2.8. Tabla: registropersonal (Seguimiento de sueño, energía y humor - HU-08)
CREATE TABLE IF NOT EXISTS registropersonal (
    id SERIAL PRIMARY KEY,
    id_usuario INT4 NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    nombre VARCHAR(120) NOT NULL,
    valorobjetivo NUMERIC(10,2) NOT NULL CHECK (valorobjetivo > 0),
    valoractual NUMERIC(10,2) NOT NULL DEFAULT 0,
    progresoporcentaje NUMERIC(5,2) NOT NULL DEFAULT 0
);

-- 2.9. Tabla: metafinanciera (Metas de ahorro y control de gastos - HU-09)
CREATE TABLE IF NOT EXISTS metafinanciera (
    id SERIAL PRIMARY KEY,
    id_usuario INT4 NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    nombre VARCHAR(150) NOT NULL,
    valorobjetivo NUMERIC(12,2) NOT NULL CHECK (valorobjetivo > 0),
    valoractual NUMERIC(12,2) NOT NULL DEFAULT 0,
    progresoporcentaje NUMERIC(5,2) NOT NULL DEFAULT 0
);

-- 2.10. Tabla: panelprincipal (Snapshot diario del Dashboard - HU-10)
CREATE TABLE IF NOT EXISTS panelprincipal (
    id SERIAL PRIMARY KEY,
    id_usuario INT4 NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    fechaactual DATE NOT NULL DEFAULT CURRENT_DATE
);

-- -----------------------------------------------------------------------------
-- 3. ÍNDICES DE OPTIMIZACIÓN
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_usuario_correo ON usuario(correo);

CREATE INDEX IF NOT EXISTS idx_rutina_usuario ON rutina(id_usuario);
CREATE INDEX IF NOT EXISTS idx_rutina_usuario_completada ON rutina(id_usuario, completadahoy);

CREATE INDEX IF NOT EXISTS idx_tarea_usuario ON tarea(id_usuario);
CREATE INDEX IF NOT EXISTS idx_tarea_rutina ON tarea(id_rutina);
CREATE INDEX IF NOT EXISTS idx_tarea_usuario_estado_prioridad ON tarea(id_usuario, completada, prioridad);
CREATE INDEX IF NOT EXISTS idx_tarea_fechavencimiento ON tarea(fechavencimiento);

CREATE INDEX IF NOT EXISTS idx_subtarea_tarea ON subtarea(id_tarea);

CREATE INDEX IF NOT EXISTS idx_sesionpomodoro_usuario ON sesionpomodoro(id_usuario);
CREATE INDEX IF NOT EXISTS idx_sesionpomodoro_tarea ON sesionpomodoro(id_tarea);

CREATE INDEX IF NOT EXISTS idx_recordatorio_usuario_fechahora ON recordatorio(id_usuario, fechahora);
CREATE INDEX IF NOT EXISTS idx_recordatorio_tarea ON recordatorio(id_tarea);

CREATE INDEX IF NOT EXISTS idx_recompensa_tarea ON recompensa(id_tarea);
CREATE INDEX IF NOT EXISTS idx_recompensa_desbloqueada ON recompensa(desbloqueada);

CREATE INDEX IF NOT EXISTS idx_registropersonal_usuario ON registropersonal(id_usuario);
CREATE INDEX IF NOT EXISTS idx_metafinanciera_usuario ON metafinanciera(id_usuario);
CREATE INDEX IF NOT EXISTS idx_panelprincipal_usuario_fecha ON panelprincipal(id_usuario, fechaactual);
