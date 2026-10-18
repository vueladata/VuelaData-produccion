-- VuelaData - esquema operacional para PostgreSQL 15+
-- Todos los instantes se almacenan como timestamptz y se reciben en UTC.
-- Este script crea únicamente el modelo operacional; F1 pertenece al Data Lake analítico.

CREATE SCHEMA IF NOT EXISTS vueladata;
SET search_path TO vueladata, public;
SET TIME ZONE 'UTC';

-- ================================================================
-- Catálogos geográficos, flota y operación de vuelos
-- ================================================================

CREATE TABLE pais (
    id_pais bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre varchar(100) NOT NULL,
    codigo_iso varchar(3) NOT NULL UNIQUE,
    CONSTRAINT ck_pais_codigo_iso CHECK (codigo_iso = upper(codigo_iso))
);

CREATE TABLE ciudad (
    id_ciudad bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_pais bigint NOT NULL REFERENCES pais(id_pais),
    nombre varchar(120) NOT NULL,
    CONSTRAINT uq_ciudad_pais_nombre UNIQUE (id_pais, nombre)
);

CREATE TABLE aeropuerto (
    id_aeropuerto bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_ciudad bigint NOT NULL REFERENCES ciudad(id_ciudad),
    codigo_iata varchar(3) NOT NULL UNIQUE,
    codigo_icao varchar(4) UNIQUE,
    nombre varchar(180) NOT NULL,
    latitud numeric(8,5) NOT NULL,
    longitud numeric(8,5) NOT NULL,
    zona_horaria varchar(64) NOT NULL,
    es_hub boolean NOT NULL DEFAULT false,
    CONSTRAINT ck_aeropuerto_latitud CHECK (latitud BETWEEN -90 AND 90),
    CONSTRAINT ck_aeropuerto_longitud CHECK (longitud BETWEEN -180 AND 180),
    CONSTRAINT ck_aeropuerto_iata CHECK (codigo_iata = upper(codigo_iata)),
    CONSTRAINT ck_aeropuerto_icao CHECK (codigo_icao IS NULL OR codigo_icao = upper(codigo_icao))
);

CREATE TABLE aerolinea (
    id_aerolinea bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_iata varchar(3) NOT NULL UNIQUE,
    nombre varchar(180) NOT NULL,
    CONSTRAINT ck_aerolinea_iata CHECK (codigo_iata = upper(codigo_iata))
);

CREATE TABLE aeronave (
    id_aeronave bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_aerolinea bigint NOT NULL REFERENCES aerolinea(id_aerolinea),
    matricula varchar(20) NOT NULL UNIQUE,
    modelo varchar(100) NOT NULL,
    capacidad_pasajeros integer NOT NULL,
    estado_operativo varchar(30) NOT NULL,
    -- Identificador ICAO24 de OpenSky. Puede ser nulo si la aeronave no es rastreable por F2.
    codigo_icao24 varchar(6) UNIQUE,
    CONSTRAINT ck_aeronave_capacidad CHECK (capacidad_pasajeros > 0),
    CONSTRAINT ck_aeronave_icao24 CHECK (codigo_icao24 IS NULL OR codigo_icao24 ~ '^[0-9A-Fa-f]{6}$')
);

CREATE TABLE ruta (
    id_ruta bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_aeropuerto_origen bigint NOT NULL REFERENCES aeropuerto(id_aeropuerto),
    id_aeropuerto_destino bigint NOT NULL REFERENCES aeropuerto(id_aeropuerto),
    duracion_estimada_min integer NOT NULL,
    CONSTRAINT uq_ruta_origen_destino UNIQUE (id_aeropuerto_origen, id_aeropuerto_destino),
    CONSTRAINT ck_ruta_aeropuertos_distintos CHECK (id_aeropuerto_origen <> id_aeropuerto_destino),
    CONSTRAINT ck_ruta_duracion CHECK (duracion_estimada_min > 0)
);

CREATE TABLE estado_vuelo (
    id_estado_vuelo smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(40) NOT NULL UNIQUE,
    nombre varchar(100) NOT NULL,
    descripcion varchar(300)
);

CREATE TABLE vuelo (
    id_vuelo bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_ruta bigint NOT NULL REFERENCES ruta(id_ruta),
    id_aeronave bigint NOT NULL REFERENCES aeronave(id_aeronave),
    numero_vuelo varchar(12) NOT NULL,
    salida_programada_utc timestamptz NOT NULL,
    llegada_programada_utc timestamptz NOT NULL,
    salida_real_puerta_utc timestamptz,
    despegue_real_utc timestamptz,
    aterrizaje_real_utc timestamptz,
    llegada_real_puerta_utc timestamptz,
    id_estado_vuelo_actual smallint NOT NULL REFERENCES estado_vuelo(id_estado_vuelo),
    id_aeropuerto_desvio bigint REFERENCES aeropuerto(id_aeropuerto),
    CONSTRAINT uq_vuelo_numero_salida UNIQUE (numero_vuelo, salida_programada_utc),
    CONSTRAINT ck_vuelo_programacion CHECK (llegada_programada_utc > salida_programada_utc),
    CONSTRAINT ck_vuelo_salida_puerta CHECK (
        salida_real_puerta_utc IS NULL OR salida_real_puerta_utc >= salida_programada_utc - interval '24 hours'
    ),
    CONSTRAINT ck_vuelo_oooi CHECK (
        (despegue_real_utc IS NULL OR salida_real_puerta_utc IS NULL OR despegue_real_utc >= salida_real_puerta_utc)
        AND (aterrizaje_real_utc IS NULL OR despegue_real_utc IS NULL OR aterrizaje_real_utc >= despegue_real_utc)
        AND (llegada_real_puerta_utc IS NULL OR aterrizaje_real_utc IS NULL OR llegada_real_puerta_utc >= aterrizaje_real_utc)
    )
);

CREATE TABLE evento_operacional (
    id_evento bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vuelo bigint NOT NULL REFERENCES vuelo(id_vuelo),
    id_estado_vuelo smallint NOT NULL REFERENCES estado_vuelo(id_estado_vuelo),
    fecha_hora_evento_utc timestamptz NOT NULL,
    fecha_hora_recepcion_utc timestamptz NOT NULL DEFAULT now(),
    codigo_evento varchar(40) NOT NULL,
    codigo_causa_original varchar(50),
    -- Clave idempotente de F4; el consumidor debe construirla si el proveedor no la entrega.
    id_externo_evento varchar(150) NOT NULL UNIQUE,
    estado_validacion varchar(20) NOT NULL DEFAULT 'PENDIENTE',
    detalle_validacion varchar(500),
    fecha_procesamiento_utc timestamptz,
    CONSTRAINT ck_evento_estado_validacion CHECK (estado_validacion IN ('PENDIENTE', 'VALIDO', 'RECHAZADO'))
);

CREATE TABLE posicion_aeronave (
    id_posicion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_aeronave bigint NOT NULL REFERENCES aeronave(id_aeronave),
    fecha_hora_posicion_utc timestamptz NOT NULL,
    fecha_hora_recepcion_utc timestamptz NOT NULL DEFAULT now(),
    latitud numeric(8,5) NOT NULL,
    longitud numeric(8,5) NOT NULL,
    altitud_m numeric(10,2),
    velocidad_kmh numeric(8,2),
    rumbo_grados numeric(6,2),
    en_tierra boolean NOT NULL,
    -- F2 puede usar la composición ICAO24 + time_position como esta clave.
    id_externo_posicion varchar(150) NOT NULL UNIQUE,
    CONSTRAINT ck_posicion_latitud CHECK (latitud BETWEEN -90 AND 90),
    CONSTRAINT ck_posicion_longitud CHECK (longitud BETWEEN -180 AND 180),
    CONSTRAINT ck_posicion_altitud CHECK (altitud_m IS NULL OR altitud_m >= -500),
    CONSTRAINT ck_posicion_velocidad CHECK (velocidad_kmh IS NULL OR velocidad_kmh >= 0),
    CONSTRAINT ck_posicion_rumbo CHECK (rumbo_grados IS NULL OR rumbo_grados >= 0 AND rumbo_grados < 360)
);

CREATE TABLE observacion_clima (
    id_observacion_clima bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_aeropuerto bigint NOT NULL REFERENCES aeropuerto(id_aeropuerto),
    fecha_hora_observacion_utc timestamptz NOT NULL,
    fecha_hora_recepcion_utc timestamptz NOT NULL DEFAULT now(),
    visibilidad_km numeric(6,2),
    velocidad_viento_kmh numeric(6,2),
    direccion_viento_grados numeric(6,2),
    temperatura_c numeric(5,2),
    precipitacion_mm numeric(7,2),
    codigo_clima varchar(30),
    CONSTRAINT uq_clima_aeropuerto_instante UNIQUE (id_aeropuerto, fecha_hora_observacion_utc),
    CONSTRAINT ck_clima_visibilidad CHECK (visibilidad_km IS NULL OR visibilidad_km >= 0),
    CONSTRAINT ck_clima_viento CHECK (velocidad_viento_kmh IS NULL OR velocidad_viento_kmh >= 0),
    CONSTRAINT ck_clima_direccion CHECK (direccion_viento_grados IS NULL OR direccion_viento_grados >= 0 AND direccion_viento_grados < 360),
    CONSTRAINT ck_clima_precipitacion CHECK (precipitacion_mm IS NULL OR precipitacion_mm >= 0)
);

-- ================================================================
-- Reservas, itinerarios y conexiones de pasajeros
-- ================================================================

CREATE TABLE pasajero (
    id_pasajero bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre varchar(100) NOT NULL,
    apellido varchar(100) NOT NULL,
    documento varchar(50) NOT NULL,
    tipo_documento varchar(30) NOT NULL,
    fecha_nacimiento date NOT NULL,
    correo varchar(254),
    telefono varchar(30),
    CONSTRAINT uq_pasajero_documento UNIQUE (tipo_documento, documento),
    CONSTRAINT ck_pasajero_fecha_nacimiento CHECK (fecha_nacimiento < current_date)
);

CREATE TABLE reserva (
    id_reserva bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_reserva varchar(20) NOT NULL UNIQUE,
    fecha_reserva_utc timestamptz NOT NULL DEFAULT now(),
    estado_reserva varchar(30) NOT NULL,
    fecha_actualizacion_utc timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reserva_pasajero (
    id_reserva_pasajero bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva bigint NOT NULL REFERENCES reserva(id_reserva),
    id_pasajero bigint NOT NULL REFERENCES pasajero(id_pasajero),
    CONSTRAINT uq_reserva_pasajero UNIQUE (id_reserva, id_pasajero)
);

CREATE TABLE itinerario (
    id_itinerario bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva_pasajero bigint NOT NULL REFERENCES reserva_pasajero(id_reserva_pasajero),
    fecha_salida_utc timestamptz NOT NULL,
    estado varchar(30) NOT NULL,
    fecha_creacion_utc timestamptz NOT NULL DEFAULT now(),
    fecha_actualizacion_utc timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE detalle_reserva (
    id_detalle_reserva bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_itinerario bigint NOT NULL REFERENCES itinerario(id_itinerario),
    id_vuelo bigint NOT NULL REFERENCES vuelo(id_vuelo),
    numero_secuencia integer NOT NULL,
    clase_servicio varchar(40) NOT NULL,
    clase_tarifaria varchar(20),
    monto_tarifa_pagada numeric(12,2) NOT NULL,
    moneda varchar(3) NOT NULL,
    numero_asiento varchar(10),
    estado_segmento varchar(30) NOT NULL,
    CONSTRAINT uq_detalle_itinerario_secuencia UNIQUE (id_itinerario, numero_secuencia),
    CONSTRAINT uq_asiento_vuelo UNIQUE (id_vuelo, numero_asiento),
    CONSTRAINT ck_detalle_secuencia CHECK (numero_secuencia > 0),
    CONSTRAINT ck_detalle_tarifa CHECK (monto_tarifa_pagada >= 0),
    CONSTRAINT ck_detalle_moneda CHECK (moneda = upper(moneda))
);

CREATE TABLE checkin (
    id_checkin bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_detalle_reserva bigint NOT NULL UNIQUE REFERENCES detalle_reserva(id_detalle_reserva),
    fecha_hora_checkin_utc timestamptz NOT NULL,
    estado_checkin varchar(30) NOT NULL,
    numero_tarjeta_embarque varchar(60) UNIQUE,
    equipaje_cantidad smallint NOT NULL DEFAULT 0,
    equipaje_peso numeric(7,2) NOT NULL DEFAULT 0,
    CONSTRAINT ck_checkin_equipaje_cantidad CHECK (equipaje_cantidad >= 0),
    CONSTRAINT ck_checkin_equipaje_peso CHECK (equipaje_peso >= 0)
);

CREATE TABLE tiempo_minimo_conexion (
    id_regla_conexion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_aeropuerto bigint NOT NULL REFERENCES aeropuerto(id_aeropuerto),
    tipo_llegada varchar(20) NOT NULL,
    tipo_salida varchar(20) NOT NULL,
    minutos_minimos integer NOT NULL,
    vigente_desde_utc timestamptz NOT NULL,
    vigente_hasta_utc timestamptz,
    CONSTRAINT uq_regla_conexion_version UNIQUE (id_aeropuerto, tipo_llegada, tipo_salida, vigente_desde_utc),
    CONSTRAINT ck_regla_conexion_tipo_llegada CHECK (tipo_llegada IN ('NACIONAL', 'INTERNACIONAL')),
    CONSTRAINT ck_regla_conexion_tipo_salida CHECK (tipo_salida IN ('NACIONAL', 'INTERNACIONAL')),
    CONSTRAINT ck_regla_conexion_minutos CHECK (minutos_minimos > 0),
    CONSTRAINT ck_regla_conexion_vigencia CHECK (vigente_hasta_utc IS NULL OR vigente_hasta_utc > vigente_desde_utc)
);

CREATE TABLE conexion_itinerario (
    id_conexion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_regla_conexion bigint NOT NULL REFERENCES tiempo_minimo_conexion(id_regla_conexion),
    id_detalle_reserva_llegada bigint NOT NULL REFERENCES detalle_reserva(id_detalle_reserva),
    id_detalle_reserva_salida bigint NOT NULL REFERENCES detalle_reserva(id_detalle_reserva),
    CONSTRAINT uq_conexion_detalles UNIQUE (id_detalle_reserva_llegada, id_detalle_reserva_salida),
    CONSTRAINT ck_conexion_detalles_distintos CHECK (id_detalle_reserva_llegada <> id_detalle_reserva_salida)
);

CREATE TABLE evaluacion_conexion (
    id_evaluacion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_conexion bigint NOT NULL REFERENCES conexion_itinerario(id_conexion),
    fecha_evaluacion_utc timestamptz NOT NULL DEFAULT now(),
    llegada_estimada_utc timestamptz NOT NULL,
    salida_estimada_utc timestamptz NOT NULL,
    minutos_disponibles integer NOT NULL,
    minutos_requeridos integer NOT NULL,
    estado varchar(20) NOT NULL,
    -- El tiempo disponible puede ser negativo cuando la conexión ya se perdió.
    CONSTRAINT ck_evaluacion_minutos CHECK (minutos_requeridos > 0),
    CONSTRAINT ck_evaluacion_estado CHECK (estado IN ('NORMAL', 'EN_RIESGO', 'PERDIDA'))
);

-- ================================================================
-- Incidencias, auditoría, propagación y atención al pasajero
-- ================================================================

CREATE TABLE causa (
    id_causa smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(40) NOT NULL UNIQUE,
    nombre varchar(120) NOT NULL,
    descripcion varchar(500),
    es_imputable boolean NOT NULL
);

CREATE TABLE incidencia_vuelo (
    id_incidencia bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vuelo bigint NOT NULL REFERENCES vuelo(id_vuelo),
    id_evento_origen bigint NOT NULL UNIQUE REFERENCES evento_operacional(id_evento),
    id_causa smallint NOT NULL REFERENCES causa(id_causa),
    tipo varchar(20) NOT NULL,
    minutos_retraso integer,
    es_causa_principal boolean NOT NULL DEFAULT true,
    requiere_auditoria boolean NOT NULL DEFAULT false,
    estado_revision varchar(30) NOT NULL DEFAULT 'PENDIENTE',
    fecha_clasificacion_utc timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_incidencia_tipo CHECK (tipo IN ('RETRASO', 'CANCELACION')),
    CONSTRAINT ck_incidencia_retraso CHECK (
        (tipo = 'RETRASO' AND minutos_retraso IS NOT NULL AND minutos_retraso >= 0)
        OR (tipo = 'CANCELACION' AND minutos_retraso IS NULL)
    ),
    CONSTRAINT ck_incidencia_revision CHECK (estado_revision IN ('PENDIENTE', 'APROBADA', 'RECHAZADA'))
);

CREATE TABLE auditoria_causa (
    id_auditoria bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_incidencia bigint NOT NULL UNIQUE REFERENCES incidencia_vuelo(id_incidencia),
    id_observacion_clima_origen bigint REFERENCES observacion_clima(id_observacion_clima),
    id_observacion_clima_destino bigint REFERENCES observacion_clima(id_observacion_clima),
    motivo varchar(500) NOT NULL,
    estado varchar(30) NOT NULL DEFAULT 'PENDIENTE',
    fecha_creacion_utc timestamptz NOT NULL DEFAULT now(),
    fecha_resolucion_utc timestamptz,
    CONSTRAINT ck_auditoria_clima_presente CHECK (
        id_observacion_clima_origen IS NOT NULL OR id_observacion_clima_destino IS NOT NULL
    ),
    CONSTRAINT ck_auditoria_estado CHECK (estado IN ('PENDIENTE', 'CONFIRMADA', 'DESCARTADA'))
);

CREATE TABLE regla_rotacion (
    id_regla_rotacion smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_vuelo varchar(20) NOT NULL,
    minutos_minimos integer NOT NULL,
    vigente_desde_utc timestamptz NOT NULL,
    vigente_hasta_utc timestamptz,
    CONSTRAINT uq_regla_rotacion_version UNIQUE (tipo_vuelo, vigente_desde_utc),
    CONSTRAINT ck_regla_rotacion_tipo CHECK (tipo_vuelo IN ('NACIONAL', 'INTERNACIONAL')),
    CONSTRAINT ck_regla_rotacion_minutos CHECK (minutos_minimos > 0),
    CONSTRAINT ck_regla_rotacion_vigencia CHECK (vigente_hasta_utc IS NULL OR vigente_hasta_utc > vigente_desde_utc)
);

CREATE TABLE proyeccion_propagacion (
    id_proyeccion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vuelo_origen bigint NOT NULL REFERENCES vuelo(id_vuelo),
    id_vuelo_afectado bigint NOT NULL REFERENCES vuelo(id_vuelo),
    id_regla_rotacion smallint NOT NULL REFERENCES regla_rotacion(id_regla_rotacion),
    retraso_origen_min integer NOT NULL,
    retraso_proyectado_min integer NOT NULL,
    fecha_calculo_utc timestamptz NOT NULL DEFAULT now(),
    estado varchar(30) NOT NULL,
    CONSTRAINT ck_proyeccion_vuelos_distintos CHECK (id_vuelo_origen <> id_vuelo_afectado),
    CONSTRAINT ck_proyeccion_minutos CHECK (retraso_origen_min >= 0 AND retraso_proyectado_min >= 0),
    CONSTRAINT ck_proyeccion_estado CHECK (estado IN ('PROYECTADA', 'CONFIRMADA', 'DESCARTADA'))
);

CREATE TABLE regla_compensacion (
    id_regla_compensacion smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_incidencia varchar(20) NOT NULL,
    minutos_minimos integer,
    minutos_maximos integer,
    aviso_max_horas integer,
    porcentaje numeric(5,4) NOT NULL,
    requiere_reubicacion boolean NOT NULL DEFAULT false,
    vigente_desde_utc timestamptz NOT NULL,
    vigente_hasta_utc timestamptz,
    CONSTRAINT ck_regla_comp_tipo CHECK (tipo_incidencia IN ('RETRASO', 'CANCELACION')),
    CONSTRAINT ck_regla_comp_porcentaje CHECK (porcentaje BETWEEN 0 AND 1),
    CONSTRAINT ck_regla_comp_vigencia CHECK (vigente_hasta_utc IS NULL OR vigente_hasta_utc > vigente_desde_utc),
    CONSTRAINT ck_regla_comp_retraso CHECK (
        (tipo_incidencia = 'RETRASO'
            AND minutos_minimos IS NOT NULL
            AND minutos_minimos >= 0
            AND (minutos_maximos IS NULL OR minutos_maximos > minutos_minimos)
            AND aviso_max_horas IS NULL)
        OR
        (tipo_incidencia = 'CANCELACION'
            AND minutos_minimos IS NULL
            AND minutos_maximos IS NULL
            AND aviso_max_horas IS NOT NULL
            AND aviso_max_horas >= 0)
    )
);

CREATE TABLE compensacion (
    id_compensacion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Garantiza una compensación económica como máximo por pasajero y segmento.
    id_detalle_reserva bigint NOT NULL UNIQUE REFERENCES detalle_reserva(id_detalle_reserva),
    id_incidencia bigint NOT NULL REFERENCES incidencia_vuelo(id_incidencia),
    id_regla_compensacion smallint NOT NULL REFERENCES regla_compensacion(id_regla_compensacion),
    minutos_imputables integer,
    monto numeric(12,2) NOT NULL,
    moneda varchar(3) NOT NULL,
    fecha_calculo_utc timestamptz NOT NULL DEFAULT now(),
    estado varchar(30) NOT NULL,
    CONSTRAINT ck_compensacion_minutos CHECK (minutos_imputables IS NULL OR minutos_imputables >= 0),
    CONSTRAINT ck_compensacion_monto CHECK (monto >= 0),
    CONSTRAINT ck_compensacion_moneda CHECK (moneda = upper(moneda)),
    CONSTRAINT ck_compensacion_estado CHECK (estado IN ('CALCULADA', 'SOLICITADA', 'PAGADA', 'RECHAZADA', 'ANULADA'))
);

CREATE TABLE pago (
    id_pago bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_compensacion bigint NOT NULL UNIQUE REFERENCES compensacion(id_compensacion),
    clave_idempotencia varchar(150) NOT NULL UNIQUE,
    -- Es nula hasta que F7 responda. PostgreSQL permite varios NULL en una columna UNIQUE.
    id_transaccion_externa varchar(150) UNIQUE,
    estado varchar(30) NOT NULL,
    fecha_solicitud_utc timestamptz NOT NULL DEFAULT now(),
    fecha_actualizacion_utc timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pago_estado CHECK (estado IN ('PENDIENTE', 'PAGADO', 'RECHAZADO'))
);

CREATE TABLE evento_pago (
    id_evento_pago bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_pago bigint NOT NULL REFERENCES pago(id_pago),
    id_externo_evento varchar(150) NOT NULL UNIQUE,
    estado_reportado varchar(30) NOT NULL,
    fecha_hora_evento_utc timestamptz NOT NULL,
    fecha_hora_recepcion_utc timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_evento_pago_estado CHECK (estado_reportado IN ('PENDIENTE', 'PAGADO', 'RECHAZADO'))
);

CREATE TABLE reubicacion (
    id_reubicacion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_detalle_reserva bigint NOT NULL REFERENCES detalle_reserva(id_detalle_reserva),
    id_incidencia bigint NOT NULL REFERENCES incidencia_vuelo(id_incidencia),
    id_vuelo_propuesto bigint REFERENCES vuelo(id_vuelo),
    estado varchar(30) NOT NULL,
    fecha_oferta_utc timestamptz,
    fecha_respuesta_utc timestamptz,
    CONSTRAINT ck_reubicacion_estado CHECK (estado IN ('PENDIENTE', 'OFRECIDA', 'ACEPTADA', 'RECHAZADA', 'COMPLETADA')),
    CONSTRAINT ck_reubicacion_respuesta CHECK (fecha_respuesta_utc IS NULL OR fecha_oferta_utc IS NULL OR fecha_respuesta_utc >= fecha_oferta_utc)
);

CREATE TABLE notificacion (
    id_notificacion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_detalle_reserva bigint NOT NULL REFERENCES detalle_reserva(id_detalle_reserva),
    id_evaluacion_conexion bigint REFERENCES evaluacion_conexion(id_evaluacion),
    id_compensacion bigint REFERENCES compensacion(id_compensacion),
    tipo varchar(30) NOT NULL,
    canal varchar(20) NOT NULL,
    estado_envio varchar(30) NOT NULL,
    fecha_programada_utc timestamptz NOT NULL DEFAULT now(),
    fecha_envio_utc timestamptz,
    CONSTRAINT ck_notificacion_tipo CHECK (tipo IN ('CONEXION_RIESGO', 'COMPENSACION', 'REUBICACION', 'INTERRUPCION')),
    CONSTRAINT ck_notificacion_canal CHECK (canal IN ('EMAIL', 'SMS', 'PUSH')),
    CONSTRAINT ck_notificacion_estado CHECK (estado_envio IN ('PENDIENTE', 'ENVIADA', 'FALLIDA')),
    CONSTRAINT ck_notificacion_origen CHECK (
        (tipo <> 'CONEXION_RIESGO' OR id_evaluacion_conexion IS NOT NULL)
        AND (tipo <> 'COMPENSACION' OR id_compensacion IS NOT NULL)
    )
);

-- ================================================================
-- Índices para consultas operacionales y consumo de streams
-- ================================================================

CREATE INDEX ix_vuelo_aeronave_programacion ON vuelo (id_aeronave, salida_programada_utc);
CREATE INDEX ix_vuelo_ruta_programacion ON vuelo (id_ruta, salida_programada_utc);
CREATE INDEX ix_evento_operacional_vuelo_instante ON evento_operacional (id_vuelo, fecha_hora_evento_utc DESC);
CREATE INDEX ix_evento_operacional_validacion ON evento_operacional (estado_validacion, fecha_hora_recepcion_utc);
CREATE INDEX ix_posicion_aeronave_instante ON posicion_aeronave (id_aeronave, fecha_hora_posicion_utc DESC);
CREATE INDEX ix_clima_aeropuerto_instante ON observacion_clima (id_aeropuerto, fecha_hora_observacion_utc DESC);
CREATE INDEX ix_detalle_reserva_vuelo ON detalle_reserva (id_vuelo);
CREATE INDEX ix_evaluacion_conexion_reciente ON evaluacion_conexion (id_conexion, fecha_evaluacion_utc DESC);
CREATE INDEX ix_incidencia_vuelo ON incidencia_vuelo (id_vuelo, fecha_clasificacion_utc DESC);
CREATE INDEX ix_proyeccion_origen ON proyeccion_propagacion (id_vuelo_origen, fecha_calculo_utc DESC);
CREATE INDEX ix_pago_estado ON pago (estado, fecha_actualizacion_utc);
CREATE INDEX ix_evento_pago_pago ON evento_pago (id_pago, fecha_hora_evento_utc DESC);
CREATE INDEX ix_notificacion_pendiente ON notificacion (estado_envio, fecha_programada_utc) WHERE estado_envio = 'PENDIENTE';
CREATE UNIQUE INDEX uq_notificacion_conexion_canal
    ON notificacion (id_evaluacion_conexion, canal)
    WHERE id_evaluacion_conexion IS NOT NULL;
CREATE UNIQUE INDEX uq_notificacion_compensacion_canal
    ON notificacion (id_compensacion, canal)
    WHERE id_compensacion IS NOT NULL;

-- ================================================================
-- Funciones y triggers de reglas de negocio
-- ================================================================

CREATE OR REPLACE FUNCTION fn_validar_conexion_itinerario()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_itinerario_llegada bigint;
    v_itinerario_salida bigint;
    v_secuencia_llegada integer;
    v_secuencia_salida integer;
    v_aeropuerto_llegada bigint;
    v_aeropuerto_salida bigint;
    v_aeropuerto_regla bigint;
BEGIN
    SELECT d.id_itinerario, d.numero_secuencia, r.id_aeropuerto_destino
      INTO v_itinerario_llegada, v_secuencia_llegada, v_aeropuerto_llegada
      FROM detalle_reserva d
      JOIN vuelo v ON v.id_vuelo = d.id_vuelo
      JOIN ruta r ON r.id_ruta = v.id_ruta
     WHERE d.id_detalle_reserva = NEW.id_detalle_reserva_llegada;

    SELECT d.id_itinerario, d.numero_secuencia, r.id_aeropuerto_origen
      INTO v_itinerario_salida, v_secuencia_salida, v_aeropuerto_salida
      FROM detalle_reserva d
      JOIN vuelo v ON v.id_vuelo = d.id_vuelo
      JOIN ruta r ON r.id_ruta = v.id_ruta
     WHERE d.id_detalle_reserva = NEW.id_detalle_reserva_salida;

    SELECT id_aeropuerto
      INTO v_aeropuerto_regla
      FROM tiempo_minimo_conexion
     WHERE id_regla_conexion = NEW.id_regla_conexion;

    IF v_itinerario_llegada IS DISTINCT FROM v_itinerario_salida THEN
        RAISE EXCEPTION 'Los detalles de una conexión deben pertenecer al mismo itinerario';
    END IF;

    IF v_secuencia_salida <> v_secuencia_llegada + 1 THEN
        RAISE EXCEPTION 'Los segmentos de una conexión deben ser consecutivos';
    END IF;

    IF v_aeropuerto_llegada <> v_aeropuerto_salida
       OR v_aeropuerto_llegada <> v_aeropuerto_regla THEN
        RAISE EXCEPTION 'Los vuelos y la regla deben coincidir en el aeropuerto de conexión';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_conexion_itinerario
BEFORE INSERT OR UPDATE OF id_regla_conexion, id_detalle_reserva_llegada, id_detalle_reserva_salida
ON conexion_itinerario
FOR EACH ROW EXECUTE FUNCTION fn_validar_conexion_itinerario();

CREATE OR REPLACE FUNCTION fn_validar_auditoria_clima()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_aeropuerto_origen bigint;
    v_aeropuerto_destino bigint;
    v_fecha_evento timestamptz;
    v_aeropuerto_clima bigint;
    v_fecha_clima timestamptz;
BEGIN
    SELECT r.id_aeropuerto_origen, r.id_aeropuerto_destino, e.fecha_hora_evento_utc
      INTO v_aeropuerto_origen, v_aeropuerto_destino, v_fecha_evento
      FROM incidencia_vuelo i
      JOIN vuelo v ON v.id_vuelo = i.id_vuelo
      JOIN ruta r ON r.id_ruta = v.id_ruta
      JOIN evento_operacional e ON e.id_evento = i.id_evento_origen
     WHERE i.id_incidencia = NEW.id_incidencia;

    IF NEW.id_observacion_clima_origen IS NOT NULL THEN
        SELECT id_aeropuerto, fecha_hora_observacion_utc
          INTO v_aeropuerto_clima, v_fecha_clima
          FROM observacion_clima
         WHERE id_observacion_clima = NEW.id_observacion_clima_origen;

        IF v_aeropuerto_clima <> v_aeropuerto_origen
           OR abs(extract(epoch FROM (v_fecha_clima - v_fecha_evento))) > 3600 THEN
            RAISE EXCEPTION 'La observación de origen debe corresponder al aeropuerto y hora de la incidencia';
        END IF;
    END IF;

    IF NEW.id_observacion_clima_destino IS NOT NULL THEN
        SELECT id_aeropuerto, fecha_hora_observacion_utc
          INTO v_aeropuerto_clima, v_fecha_clima
          FROM observacion_clima
         WHERE id_observacion_clima = NEW.id_observacion_clima_destino;

        IF v_aeropuerto_clima <> v_aeropuerto_destino
           OR abs(extract(epoch FROM (v_fecha_clima - v_fecha_evento))) > 3600 THEN
            RAISE EXCEPTION 'La observación de destino debe corresponder al aeropuerto y hora de la incidencia';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_auditoria_clima
BEFORE INSERT OR UPDATE OF id_incidencia, id_observacion_clima_origen, id_observacion_clima_destino
ON auditoria_causa
FOR EACH ROW EXECUTE FUNCTION fn_validar_auditoria_clima();

CREATE OR REPLACE FUNCTION fn_validar_proyeccion_propagacion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_aeronave_origen bigint;
    v_aeronave_afectada bigint;
    v_salida_origen timestamptz;
    v_salida_afectada timestamptz;
BEGIN
    SELECT id_aeronave, salida_programada_utc
      INTO v_aeronave_origen, v_salida_origen
      FROM vuelo WHERE id_vuelo = NEW.id_vuelo_origen;

    SELECT id_aeronave, salida_programada_utc
      INTO v_aeronave_afectada, v_salida_afectada
      FROM vuelo WHERE id_vuelo = NEW.id_vuelo_afectado;

    IF v_aeronave_origen <> v_aeronave_afectada THEN
        RAISE EXCEPTION 'La propagación solo puede ocurrir entre vuelos de la misma aeronave';
    END IF;

    IF v_salida_afectada <= v_salida_origen THEN
        RAISE EXCEPTION 'El vuelo afectado debe estar programado después del vuelo origen';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM vuelo v
         WHERE v.id_aeronave = v_aeronave_origen
           AND v.salida_programada_utc > v_salida_origen
           AND v.salida_programada_utc < v_salida_afectada
    ) THEN
        RAISE EXCEPTION 'El vuelo afectado debe ser el siguiente vuelo programado de la aeronave';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_proyeccion_propagacion
BEFORE INSERT OR UPDATE OF id_vuelo_origen, id_vuelo_afectado
ON proyeccion_propagacion
FOR EACH ROW EXECUTE FUNCTION fn_validar_proyeccion_propagacion();

CREATE OR REPLACE FUNCTION fn_validar_compensacion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_vuelo_detalle bigint;
    v_vuelo_incidencia bigint;
    v_imputable boolean;
    v_tipo_incidencia varchar(20);
    v_retraso integer;
    v_requiere_auditoria boolean;
    v_estado_revision varchar(30);
    v_fecha_evento timestamptz;
    v_salida_programada timestamptz;
    v_tipo_regla varchar(20);
    v_minutos_minimos integer;
    v_minutos_maximos integer;
    v_aviso_max_horas integer;
    v_porcentaje numeric(5,4);
    v_vigente_desde timestamptz;
    v_vigente_hasta timestamptz;
    v_tarifa numeric(12,2);
    v_moneda varchar(3);
BEGIN
    SELECT d.id_vuelo, d.monto_tarifa_pagada, d.moneda
      INTO v_vuelo_detalle, v_tarifa, v_moneda
      FROM detalle_reserva d
     WHERE d.id_detalle_reserva = NEW.id_detalle_reserva;

    SELECT i.id_vuelo, c.es_imputable, i.tipo, i.minutos_retraso,
           i.requiere_auditoria, i.estado_revision,
           e.fecha_hora_evento_utc, v.salida_programada_utc
      INTO v_vuelo_incidencia, v_imputable, v_tipo_incidencia, v_retraso,
           v_requiere_auditoria, v_estado_revision,
           v_fecha_evento, v_salida_programada
      FROM incidencia_vuelo i
      JOIN causa c ON c.id_causa = i.id_causa
      JOIN evento_operacional e ON e.id_evento = i.id_evento_origen
      JOIN vuelo v ON v.id_vuelo = i.id_vuelo
     WHERE i.id_incidencia = NEW.id_incidencia;

    SELECT tipo_incidencia, minutos_minimos, minutos_maximos, aviso_max_horas,
           porcentaje, vigente_desde_utc, vigente_hasta_utc
      INTO v_tipo_regla, v_minutos_minimos, v_minutos_maximos, v_aviso_max_horas,
           v_porcentaje, v_vigente_desde, v_vigente_hasta
      FROM regla_compensacion
     WHERE id_regla_compensacion = NEW.id_regla_compensacion;

    IF v_vuelo_detalle <> v_vuelo_incidencia THEN
        RAISE EXCEPTION 'La compensación debe corresponder al mismo vuelo del detalle de reserva';
    END IF;

    IF NOT v_imputable THEN
        RAISE EXCEPTION 'Una causa no imputable no genera compensación económica';
    END IF;

    IF v_requiere_auditoria AND v_estado_revision <> 'APROBADA' THEN
        RAISE EXCEPTION 'Una incidencia marcada para auditoría debe aprobarse antes de compensar';
    END IF;

    IF v_tipo_regla <> v_tipo_incidencia THEN
        RAISE EXCEPTION 'La regla de compensación no coincide con el tipo de incidencia';
    END IF;

    IF NEW.fecha_calculo_utc < v_vigente_desde
       OR (v_vigente_hasta IS NOT NULL AND NEW.fecha_calculo_utc >= v_vigente_hasta) THEN
        RAISE EXCEPTION 'La regla de compensación no estaba vigente al calcular la compensación';
    END IF;

    IF v_tipo_incidencia = 'RETRASO' THEN
        IF v_retraso < v_minutos_minimos
           OR (v_minutos_maximos IS NOT NULL AND v_retraso >= v_minutos_maximos) THEN
            RAISE EXCEPTION 'El retraso no cumple el rango de la regla de compensación';
        END IF;
        IF NEW.minutos_imputables <> v_retraso THEN
            RAISE EXCEPTION 'Los minutos imputables deben coincidir con el retraso clasificado';
        END IF;
    ELSE
        IF extract(epoch FROM (v_salida_programada - v_fecha_evento)) / 3600 >= v_aviso_max_horas THEN
            RAISE EXCEPTION 'La cancelación no cumple el plazo máximo de aviso de la regla';
        END IF;
    END IF;

    IF NEW.moneda <> v_moneda OR NEW.monto <> round(v_tarifa * v_porcentaje, 2) THEN
        RAISE EXCEPTION 'El monto o moneda de la compensación no coincide con la tarifa y regla aplicadas';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_compensacion
BEFORE INSERT OR UPDATE OF id_detalle_reserva, id_incidencia, id_regla_compensacion, minutos_imputables, monto, moneda, fecha_calculo_utc
ON compensacion
FOR EACH ROW EXECUTE FUNCTION fn_validar_compensacion();

CREATE OR REPLACE FUNCTION fn_validar_reubicacion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_vuelo_detalle bigint;
    v_vuelo_incidencia bigint;
BEGIN
    SELECT id_vuelo INTO v_vuelo_detalle
      FROM detalle_reserva
     WHERE id_detalle_reserva = NEW.id_detalle_reserva;

    SELECT id_vuelo INTO v_vuelo_incidencia
      FROM incidencia_vuelo
     WHERE id_incidencia = NEW.id_incidencia;

    IF v_vuelo_detalle <> v_vuelo_incidencia THEN
        RAISE EXCEPTION 'La reubicación debe pertenecer al mismo vuelo de la incidencia';
    END IF;

    IF NEW.id_vuelo_propuesto = v_vuelo_detalle THEN
        RAISE EXCEPTION 'El vuelo propuesto debe ser diferente del vuelo afectado';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_reubicacion
BEFORE INSERT OR UPDATE OF id_detalle_reserva, id_incidencia, id_vuelo_propuesto
ON reubicacion
FOR EACH ROW EXECUTE FUNCTION fn_validar_reubicacion();

-- La cancelación imputable con aviso menor de 72 horas requiere reubicación.
-- Es diferido para permitir insertar la compensación y su reubicación en la misma transacción.
CREATE OR REPLACE FUNCTION fn_validar_reubicacion_obligatoria()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_requiere_reubicacion boolean;
BEGIN
    SELECT requiere_reubicacion
      INTO v_requiere_reubicacion
      FROM regla_compensacion
     WHERE id_regla_compensacion = NEW.id_regla_compensacion;

    IF v_requiere_reubicacion
       AND NOT EXISTS (
            SELECT 1
              FROM reubicacion r
             WHERE r.id_detalle_reserva = NEW.id_detalle_reserva
               AND r.id_incidencia = NEW.id_incidencia
       ) THEN
        RAISE EXCEPTION 'La regla de compensación exige una reubicación asociada';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_validar_reubicacion_obligatoria
AFTER INSERT OR UPDATE OF id_detalle_reserva, id_incidencia, id_regla_compensacion
ON compensacion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_reubicacion_obligatoria();

CREATE OR REPLACE FUNCTION fn_validar_notificacion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_detalle_llegada bigint;
    v_detalle_salida bigint;
    v_estado_evaluacion varchar(20);
    v_detalle_compensacion bigint;
BEGIN
    IF NEW.tipo = 'CONEXION_RIESGO' THEN
        SELECT c.id_detalle_reserva_llegada, c.id_detalle_reserva_salida, e.estado
          INTO v_detalle_llegada, v_detalle_salida, v_estado_evaluacion
          FROM evaluacion_conexion e
          JOIN conexion_itinerario c ON c.id_conexion = e.id_conexion
         WHERE e.id_evaluacion = NEW.id_evaluacion_conexion;

        IF v_estado_evaluacion NOT IN ('EN_RIESGO', 'PERDIDA')
           OR NEW.id_detalle_reserva NOT IN (v_detalle_llegada, v_detalle_salida) THEN
            RAISE EXCEPTION 'La notificación de conexión debe referirse a una evaluación en riesgo del mismo itinerario';
        END IF;
    END IF;

    IF NEW.tipo = 'COMPENSACION' THEN
        SELECT id_detalle_reserva INTO v_detalle_compensacion
          FROM compensacion
         WHERE id_compensacion = NEW.id_compensacion;

        IF v_detalle_compensacion <> NEW.id_detalle_reserva THEN
            RAISE EXCEPTION 'La notificación debe pertenecer al mismo detalle de la compensación';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_notificacion
BEFORE INSERT OR UPDATE OF id_detalle_reserva, id_evaluacion_conexion, id_compensacion, tipo
ON notificacion
FOR EACH ROW EXECUTE FUNCTION fn_validar_notificacion();

-- Solo eventos validados actualizan el estado materializado del vuelo.
-- Se selecciona siempre el evento válido más reciente para tolerar mensajes fuera de orden.
CREATE OR REPLACE FUNCTION fn_actualizar_estado_vuelo_desde_evento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_reciente smallint;
BEGIN
    IF NEW.estado_validacion <> 'VALIDO' THEN
        RETURN NEW;
    END IF;

    SELECT id_estado_vuelo
      INTO v_estado_reciente
      FROM evento_operacional
     WHERE id_vuelo = NEW.id_vuelo
       AND estado_validacion = 'VALIDO'
     ORDER BY fecha_hora_evento_utc DESC, fecha_hora_recepcion_utc DESC, id_evento DESC
     LIMIT 1;

    UPDATE vuelo
       SET id_estado_vuelo_actual = v_estado_reciente,
           salida_real_puerta_utc = CASE WHEN NEW.codigo_evento IN ('OUT', 'SALIDA_PUERTA') THEN NEW.fecha_hora_evento_utc ELSE salida_real_puerta_utc END,
           despegue_real_utc = CASE WHEN NEW.codigo_evento IN ('OFF', 'DESPEGUE') THEN NEW.fecha_hora_evento_utc ELSE despegue_real_utc END,
           aterrizaje_real_utc = CASE WHEN NEW.codigo_evento IN ('ON', 'ATERRIZAJE') THEN NEW.fecha_hora_evento_utc ELSE aterrizaje_real_utc END,
           llegada_real_puerta_utc = CASE WHEN NEW.codigo_evento IN ('IN', 'LLEGADA_PUERTA') THEN NEW.fecha_hora_evento_utc ELSE llegada_real_puerta_utc END
     WHERE id_vuelo = NEW.id_vuelo;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actualizar_estado_vuelo_desde_evento
AFTER INSERT OR UPDATE OF estado_validacion, fecha_hora_evento_utc, id_estado_vuelo
ON evento_operacional
FOR EACH ROW EXECUTE FUNCTION fn_actualizar_estado_vuelo_desde_evento();

-- F7 puede enviar varios estados; Pago conserva el estado más reciente y Evento_Pago la trazabilidad.
CREATE OR REPLACE FUNCTION fn_actualizar_pago_desde_evento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE pago
       SET estado = NEW.estado_reportado,
           fecha_actualizacion_utc = GREATEST(fecha_actualizacion_utc, NEW.fecha_hora_recepcion_utc)
     WHERE id_pago = NEW.id_pago;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actualizar_pago_desde_evento
AFTER INSERT ON evento_pago
FOR EACH ROW EXECUTE FUNCTION fn_actualizar_pago_desde_evento();

-- ================================================================
-- Datos de catálogo requeridos por las reglas RN-03, RN-05 y RN-08
-- ================================================================

INSERT INTO estado_vuelo (codigo, nombre, descripcion) VALUES
    ('PROGRAMADO', 'Programado', 'Vuelo programado sin evento operacional confirmado'),
    ('SALIDA_PUERTA', 'Salida de puerta', 'Evento OUT recibido'),
    ('DESPEGADO', 'Despegado', 'Evento OFF recibido'),
    ('ATERRIZADO', 'Aterrizado', 'Evento ON recibido'),
    ('LLEGADA_PUERTA', 'Llegada a puerta', 'Evento IN recibido'),
    ('CANCELADO', 'Cancelado', 'Vuelo cancelado'),
    ('DESVIADO', 'Desviado', 'Vuelo desviado a un aeropuerto alterno')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO causa (codigo, nombre, descripcion, es_imputable) VALUES
    ('TECNICA', 'Técnica', 'Falla o mantenimiento técnico atribuible a la aerolínea', true),
    ('TRIPULACION', 'Tripulación', 'Indisponibilidad o demora de la tripulación', true),
    ('AERONAVE_ANTERIOR', 'Aeronave anterior', 'Propagación desde una operación anterior imputable', true),
    ('CLIMA', 'Clima', 'Condición meteorológica adversa', false),
    ('ATC', 'Control de tráfico aéreo', 'Restricción de control de tráfico aéreo', false),
    ('SEGURIDAD', 'Seguridad', 'Evento de seguridad', false)
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO regla_rotacion (tipo_vuelo, minutos_minimos, vigente_desde_utc, vigente_hasta_utc)
SELECT 'NACIONAL', 45, timestamptz '2020-01-01 00:00:00+00', NULL
WHERE NOT EXISTS (
    SELECT 1 FROM regla_rotacion
    WHERE tipo_vuelo = 'NACIONAL' AND vigente_desde_utc = timestamptz '2020-01-01 00:00:00+00'
);

INSERT INTO regla_rotacion (tipo_vuelo, minutos_minimos, vigente_desde_utc, vigente_hasta_utc)
SELECT 'INTERNACIONAL', 60, timestamptz '2020-01-01 00:00:00+00', NULL
WHERE NOT EXISTS (
    SELECT 1 FROM regla_rotacion
    WHERE tipo_vuelo = 'INTERNACIONAL' AND vigente_desde_utc = timestamptz '2020-01-01 00:00:00+00'
);

INSERT INTO regla_compensacion
    (tipo_incidencia, minutos_minimos, minutos_maximos, aviso_max_horas, porcentaje, requiere_reubicacion, vigente_desde_utc)
SELECT 'RETRASO', 120, 240, NULL, 0.2500, false, timestamptz '2020-01-01 00:00:00+00'
WHERE NOT EXISTS (
    SELECT 1 FROM regla_compensacion
    WHERE tipo_incidencia = 'RETRASO' AND minutos_minimos = 120 AND vigente_desde_utc = timestamptz '2020-01-01 00:00:00+00'
);

INSERT INTO regla_compensacion
    (tipo_incidencia, minutos_minimos, minutos_maximos, aviso_max_horas, porcentaje, requiere_reubicacion, vigente_desde_utc)
SELECT 'RETRASO', 240, 360, NULL, 0.5000, false, timestamptz '2020-01-01 00:00:00+00'
WHERE NOT EXISTS (
    SELECT 1 FROM regla_compensacion
    WHERE tipo_incidencia = 'RETRASO' AND minutos_minimos = 240 AND vigente_desde_utc = timestamptz '2020-01-01 00:00:00+00'
);

INSERT INTO regla_compensacion
    (tipo_incidencia, minutos_minimos, minutos_maximos, aviso_max_horas, porcentaje, requiere_reubicacion, vigente_desde_utc)
SELECT 'RETRASO', 360, NULL, NULL, 1.0000, false, timestamptz '2020-01-01 00:00:00+00'
WHERE NOT EXISTS (
    SELECT 1 FROM regla_compensacion
    WHERE tipo_incidencia = 'RETRASO' AND minutos_minimos = 360 AND vigente_desde_utc = timestamptz '2020-01-01 00:00:00+00'
);

INSERT INTO regla_compensacion
    (tipo_incidencia, minutos_minimos, minutos_maximos, aviso_max_horas, porcentaje, requiere_reubicacion, vigente_desde_utc)
SELECT 'CANCELACION', NULL, NULL, 72, 1.0000, true, timestamptz '2020-01-01 00:00:00+00'
WHERE NOT EXISTS (
    SELECT 1 FROM regla_compensacion
    WHERE tipo_incidencia = 'CANCELACION' AND aviso_max_horas = 72 AND vigente_desde_utc = timestamptz '2020-01-01 00:00:00+00'
);

