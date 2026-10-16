---
id: diccionario-datos
title: Diccionario de Datos VuelaData
sidebar_position: 2
---
# Diccionario de datos - VuelaData

## Alcance y convenciones

Este documento describe el esquema operacional `vueladata` definido en `schema_postgresql.sql`. El histórico masivo F1 se procesa en el Data Lake analítico y no forma parte de esta base transaccional.

| Convención | Significado |
|---|---|
| `id_*` | Clave primaria o clave foránea. Todas las claves primarias se generan con `IDENTITY`. |
| `_utc` | Instante almacenado en UTC mediante `timestamptz`. |
| `codigo` | Valor técnico, legible y estable para integraciones y reglas. |
| `id_externo_*` | Identificador de una fuente externa usado para idempotencia; no es una clave foránea. |
| `unique` | El valor o combinación de valores no puede repetirse. |
| `nullable` | El campo puede quedar vacío (`NULL`). |

## 1. Geografía, flota y operación

### `pais`

Catálogo de países.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_pais` | `bigint` | PK | Identificador del país. |
| `nombre` | `varchar(100)` | Obligatorio | Nombre del país. |
| `codigo_iso` | `varchar(3)` | Único, mayúsculas | Código ISO del país. |

### `ciudad`

Ciudades a las que pertenecen los aeropuertos.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_ciudad` | `bigint` | PK | Identificador de la ciudad. |
| `id_pais` | `bigint` | FK → `pais.id_pais` | País de la ciudad. |
| `nombre` | `varchar(120)` | Único con `id_pais` | Nombre de la ciudad. |

### `aeropuerto`

Aeropuertos de origen, destino, conexión o desvío.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_aeropuerto` | `bigint` | PK | Identificador del aeropuerto. |
| `id_ciudad` | `bigint` | FK → `ciudad.id_ciudad` | Ciudad donde está ubicado. |
| `codigo_iata` | `varchar(3)` | Único | Código IATA, por ejemplo `BOG`. |
| `codigo_icao` | `varchar(4)` | Único, nullable | Código ICAO, por ejemplo `SKBO`. |
| `nombre` | `varchar(180)` | Obligatorio | Nombre del aeropuerto. |
| `latitud` | `numeric(8,5)` | Entre -90 y 90 | Coordenada para consultar clima. |
| `longitud` | `numeric(8,5)` | Entre -180 y 180 | Coordenada para consultar clima. |
| `zona_horaria` | `varchar(64)` | Obligatorio | Zona IANA usada para presentar horarios locales. |
| `es_hub` | `boolean` | Por defecto `false` | Indica si el aeropuerto es centro de conexiones. |

### `aerolinea`

Catálogo de aerolíneas propietarias de aeronaves.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_aerolinea` | `bigint` | PK | Identificador de la aerolínea. |
| `codigo_iata` | `varchar(3)` | Único | Código IATA de la aerolínea. |
| `nombre` | `varchar(180)` | Obligatorio | Nombre comercial. |

### `aeronave`

Flota de la aerolínea. Cada aeronave pertenece a una sola aerolínea.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_aeronave` | `bigint` | PK | Identificador de la aeronave. |
| `id_aerolinea` | `bigint` | FK → `aerolinea.id_aerolinea` | Aerolínea propietaria. |
| `matricula` | `varchar(20)` | Única | Registro o matrícula de la aeronave. |
| `modelo` | `varchar(100)` | Obligatorio | Modelo de la aeronave. |
| `capacidad_pasajeros` | `integer` | Mayor que cero | Capacidad máxima de pasajeros. |
| `estado_operativo` | `varchar(30)` | Obligatorio | Estado de disponibilidad de la aeronave. |
| `codigo_icao24` | `varchar(6)` | Único, nullable | Identificador hexadecimal que OpenSky usa para reconocer la aeronave. |

### `ruta`

Trayecto comercial entre dos aeropuertos.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_ruta` | `bigint` | PK | Identificador de la ruta. |
| `id_aeropuerto_origen` | `bigint` | FK → `aeropuerto.id_aeropuerto` | Aeropuerto de salida. |
| `id_aeropuerto_destino` | `bigint` | FK → `aeropuerto.id_aeropuerto` | Aeropuerto de llegada. |
| `duracion_estimada_min` | `integer` | Mayor que cero | Duración planeada en minutos. |

La combinación origen-destino es única y ambos aeropuertos deben ser distintos.

### `estado_vuelo`

Catálogo de estados del vuelo. Los valores iniciales incluyen `PROGRAMADO`, `SALIDA_PUERTA`, `DESPEGADO`, `ATERRIZADO`, `LLEGADA_PUERTA`, `CANCELADO` y `DESVIADO`.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_estado_vuelo` | `smallint` | PK | Identificador del estado. |
| `codigo` | `varchar(40)` | Único | Código técnico del estado. |
| `nombre` | `varchar(100)` | Obligatorio | Nombre mostrado a usuarios. |
| `descripcion` | `varchar(300)` | Nullable | Explicación del estado. |

### `vuelo`

Instancia concreta de un vuelo programado. Contiene su programación, tiempos reales y estado actual materializado.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_vuelo` | `bigint` | PK | Identificador del vuelo. |
| `id_ruta` | `bigint` | FK → `ruta.id_ruta` | Ruta operada. |
| `id_aeronave` | `bigint` | FK → `aeronave.id_aeronave` | Aeronave asignada. |
| `numero_vuelo` | `varchar(12)` | Único con salida programada | Número comercial del vuelo. |
| `salida_programada_utc` | `timestamptz` | Obligatorio | Salida prevista de puerta. |
| `llegada_programada_utc` | `timestamptz` | Posterior a la salida | Llegada prevista a puerta. |
| `salida_real_puerta_utc` | `timestamptz` | Nullable | Evento OOOI `OUT`. |
| `despegue_real_utc` | `timestamptz` | Nullable | Evento OOOI `OFF`. |
| `aterrizaje_real_utc` | `timestamptz` | Nullable | Evento OOOI `ON`. |
| `llegada_real_puerta_utc` | `timestamptz` | Nullable | Evento OOOI `IN`; se usa en OTP. |
| `id_estado_vuelo_actual` | `smallint` | FK → `estado_vuelo.id_estado_vuelo` | Estado más reciente confirmado. |
| `id_aeropuerto_desvio` | `bigint` | FK → `aeropuerto.id_aeropuerto`, nullable | Aeropuerto real de desvío si aplica. |

### `evento_operacional`

Registro inmutable de mensajes OOOI, cancelaciones, desvíos y causas recibidos desde F4.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_evento` | `bigint` | PK | Identificador interno del evento. |
| `id_vuelo` | `bigint` | FK → `vuelo.id_vuelo` | Vuelo al que corresponde el mensaje. |
| `id_estado_vuelo` | `smallint` | FK → `estado_vuelo.id_estado_vuelo` | Estado que reporta o resulta del evento. |
| `fecha_hora_evento_utc` | `timestamptz` | Obligatorio | Momento real reportado por la fuente. |
| `fecha_hora_recepcion_utc` | `timestamptz` | Por defecto `now()` | Momento en que VuelaData recibe el mensaje. |
| `codigo_evento` | `varchar(40)` | Obligatorio | Tipo de evento, por ejemplo `OUT`, `OFF`, `ON`, `IN` o `CANCELACION`. |
| `codigo_causa_original` | `varchar(50)` | Nullable | Causa tal como fue enviada por la fuente. |
| `id_externo_evento` | `varchar(150)` | Único | Clave de idempotencia del mensaje de F4. Evita almacenar el mismo reenvío dos veces. |
| `estado_validacion` | `varchar(20)` | `PENDIENTE`, `VALIDO` o `RECHAZADO` | Resultado de las validaciones de calidad. |
| `detalle_validacion` | `varchar(500)` | Nullable | Explicación de un rechazo o alerta de calidad. |
| `fecha_procesamiento_utc` | `timestamptz` | Nullable | Momento en que el consumidor termina de procesarlo. |

Cuando un evento queda en estado `VALIDO`, un trigger actualiza el estado actual y los tiempos OOOI del vuelo.

### `posicion_aeronave`

Lecturas de telemetría recibidas desde F2/OpenSky.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_posicion` | `bigint` | PK | Identificador de la posición. |
| `id_aeronave` | `bigint` | FK → `aeronave.id_aeronave` | Aeronave ubicada. |
| `fecha_hora_posicion_utc` | `timestamptz` | Obligatorio | Instante de la posición reportada. |
| `fecha_hora_recepcion_utc` | `timestamptz` | Obligatorio | Instante de recepción en VuelaData. |
| `latitud` | `numeric(8,5)` | Entre -90 y 90 | Latitud reportada. |
| `longitud` | `numeric(8,5)` | Entre -180 y 180 | Longitud reportada. |
| `altitud_m` | `numeric(10,2)` | Nullable | Altitud en metros. |
| `velocidad_kmh` | `numeric(8,2)` | Nullable, no negativa | Velocidad en km/h. |
| `rumbo_grados` | `numeric(6,2)` | Nullable, 0 a 359.99 | Rumbo de la aeronave. |
| `en_tierra` | `boolean` | Obligatorio | Indica si la aeronave está en tierra. |
| `id_externo_posicion` | `varchar(150)` | Único | Clave de idempotencia de la lectura de OpenSky. |

### `observacion_clima`

Lecturas meteorológicas por aeropuerto desde F3/Open-Meteo. Sirven para la auditoría de causas técnicas.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_observacion_clima` | `bigint` | PK | Identificador de la observación. |
| `id_aeropuerto` | `bigint` | FK → `aeropuerto.id_aeropuerto` | Aeropuerto observado. |
| `fecha_hora_observacion_utc` | `timestamptz` | Único con aeropuerto | Hora representada por el dato climático. |
| `fecha_hora_recepcion_utc` | `timestamptz` | Obligatorio | Hora de recepción o consulta. |
| `visibilidad_km` | `numeric(6,2)` | Nullable, no negativa | Visibilidad horizontal en kilómetros. |
| `velocidad_viento_kmh` | `numeric(6,2)` | Nullable, no negativa | Velocidad del viento en km/h. |
| `direccion_viento_grados` | `numeric(6,2)` | Nullable, 0 a 359.99 | Dirección del viento. |
| `temperatura_c` | `numeric(5,2)` | Nullable | Temperatura en grados Celsius. |
| `precipitacion_mm` | `numeric(7,2)` | Nullable, no negativa | Precipitación en milímetros. |
| `codigo_clima` | `varchar(30)` | Nullable | Código de condición devuelto por Open-Meteo. |

## 2. Reservas, itinerarios y conexiones

### `pasajero`

Datos personales del pasajero.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_pasajero` | `bigint` | PK | Identificador del pasajero. |
| `nombre` | `varchar(100)` | Obligatorio | Nombres del pasajero. |
| `apellido` | `varchar(100)` | Obligatorio | Apellidos del pasajero. |
| `documento` | `varchar(50)` | Único con tipo | Número de documento. |
| `tipo_documento` | `varchar(30)` | Único con documento | Tipo de documento. |
| `fecha_nacimiento` | `date` | Anterior al día actual | Fecha de nacimiento. |
| `correo` | `varchar(254)` | Nullable | Correo para notificaciones. |
| `telefono` | `varchar(30)` | Nullable | Teléfono para notificaciones. |

### `reserva`

Reserva o localizador comercial. Puede incluir uno o varios pasajeros.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_reserva` | `bigint` | PK | Identificador interno. |
| `codigo_reserva` | `varchar(20)` | Único | Localizador de reserva. |
| `fecha_reserva_utc` | `timestamptz` | Obligatorio | Momento de creación. |
| `estado_reserva` | `varchar(30)` | Obligatorio | Estado comercial de la reserva. |
| `fecha_actualizacion_utc` | `timestamptz` | Obligatorio | Última actualización. |

### `reserva_pasajero`

Tabla puente entre una reserva y sus pasajeros.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_reserva_pasajero` | `bigint` | PK | Identificador de la asociación. |
| `id_reserva` | `bigint` | FK → `reserva.id_reserva` | Reserva compartida. |
| `id_pasajero` | `bigint` | FK → `pasajero.id_pasajero` | Pasajero incluido. |

La combinación reserva-pasajero no puede repetirse.

### `itinerario`

Recorrido de un pasajero dentro de una reserva.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_itinerario` | `bigint` | PK | Identificador del itinerario. |
| `id_reserva_pasajero` | `bigint` | FK → `reserva_pasajero.id_reserva_pasajero` | Pasajero dueño del itinerario. |
| `fecha_salida_utc` | `timestamptz` | Obligatorio | Salida planificada del viaje. |
| `estado` | `varchar(30)` | Obligatorio | Estado general del itinerario. |
| `fecha_creacion_utc` | `timestamptz` | Obligatorio | Creación del itinerario. |
| `fecha_actualizacion_utc` | `timestamptz` | Obligatorio | Última actualización. |

### `detalle_reserva`

Segmento reservado por un pasajero dentro de su itinerario. El orden de `numero_secuencia` define origen, destino y conexiones.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_detalle_reserva` | `bigint` | PK | Identificador del segmento reservado. |
| `id_itinerario` | `bigint` | FK → `itinerario.id_itinerario` | Itinerario que contiene el segmento. |
| `id_vuelo` | `bigint` | FK → `vuelo.id_vuelo` | Vuelo reservado. |
| `numero_secuencia` | `integer` | Único por itinerario, mayor que cero | Posición del segmento dentro del viaje. |
| `clase_servicio` | `varchar(40)` | Obligatorio | Clase de servicio, por ejemplo económica. |
| `clase_tarifaria` | `varchar(20)` | Nullable | Código de la clase tarifaria. |
| `monto_tarifa_pagada` | `numeric(12,2)` | No negativo | Tarifa histórica pagada por este segmento. |
| `moneda` | `varchar(3)` | Mayúsculas | Moneda de la tarifa. |
| `numero_asiento` | `varchar(10)` | Único por vuelo si existe | Asiento asignado. |
| `estado_segmento` | `varchar(30)` | Obligatorio | Estado del segmento reservado. |

### `checkin`

Proceso de check-in de un segmento reservado.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_checkin` | `bigint` | PK | Identificador del check-in. |
| `id_detalle_reserva` | `bigint` | FK único → `detalle_reserva.id_detalle_reserva` | Segmento sobre el que se realiza. |
| `fecha_hora_checkin_utc` | `timestamptz` | Obligatorio | Hora del check-in. |
| `estado_checkin` | `varchar(30)` | Obligatorio | Estado del proceso. |
| `numero_tarjeta_embarque` | `varchar(60)` | Único, nullable | Identificador de la tarjeta de embarque. |
| `equipaje_cantidad` | `smallint` | No negativo | Número de piezas registradas. |
| `equipaje_peso` | `numeric(7,2)` | No negativo | Peso total de equipaje. |

### `tiempo_minimo_conexion`

Reglas configurables de tiempo mínimo de conexión por aeropuerto y tipo de llegada/salida.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_regla_conexion` | `bigint` | PK | Identificador de la regla. |
| `id_aeropuerto` | `bigint` | FK → `aeropuerto.id_aeropuerto` | Aeropuerto donde ocurre la conexión. |
| `tipo_llegada` | `varchar(20)` | `NACIONAL` o `INTERNACIONAL` | Tipo del vuelo que llega. |
| `tipo_salida` | `varchar(20)` | `NACIONAL` o `INTERNACIONAL` | Tipo del vuelo que sale. |
| `minutos_minimos` | `integer` | Mayor que cero | Tiempo mínimo requerido para la conexión. |
| `vigente_desde_utc` | `timestamptz` | Obligatorio | Inicio de vigencia de la regla. |
| `vigente_hasta_utc` | `timestamptz` | Nullable | Fin de vigencia; vacío indica que sigue activa. |

### `conexion_itinerario`

Enlace entre dos segmentos consecutivos de un mismo pasajero.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_conexion` | `bigint` | PK | Identificador de la conexión. |
| `id_regla_conexion` | `bigint` | FK → `tiempo_minimo_conexion.id_regla_conexion` | Regla aplicada. |
| `id_detalle_reserva_llegada` | `bigint` | FK → `detalle_reserva.id_detalle_reserva` | Segmento que llega al hub. |
| `id_detalle_reserva_salida` | `bigint` | FK → `detalle_reserva.id_detalle_reserva` | Segmento siguiente que sale del hub. |

Un trigger exige que ambos segmentos pertenezcan al mismo itinerario, sean consecutivos y conecten en el aeropuerto definido por la regla.

### `evaluacion_conexion`

Historial de cálculos de una conexión. Una conexión puede evaluarse varias veces cuando cambian los horarios estimados.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_evaluacion` | `bigint` | PK | Identificador de la evaluación. |
| `id_conexion` | `bigint` | FK → `conexion_itinerario.id_conexion` | Conexión evaluada. |
| `fecha_evaluacion_utc` | `timestamptz` | Obligatorio | Momento del cálculo. |
| `llegada_estimada_utc` | `timestamptz` | Obligatorio | Hora prevista de llegada del primer segmento. |
| `salida_estimada_utc` | `timestamptz` | Obligatorio | Hora prevista de salida del siguiente segmento. |
| `minutos_disponibles` | `integer` | Puede ser negativo | Tiempo proyectado entre segmentos. Es negativo si ya se perdió la conexión. |
| `minutos_requeridos` | `integer` | Mayor que cero | Mínimo de la regla aplicada, copiado para trazabilidad. |
| `estado` | `varchar(20)` | `NORMAL`, `EN_RIESGO` o `PERDIDA` | Resultado de la evaluación. |

## 3. Incidencias, compensaciones y comunicaciones

### `causa`

Catálogo de causas normalizadas. Contiene las causas imputables y no imputables exigidas por RN-03.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_causa` | `smallint` | PK | Identificador de la causa. |
| `codigo` | `varchar(40)` | Único | Código técnico, por ejemplo `TECNICA` o `CLIMA`. |
| `nombre` | `varchar(120)` | Obligatorio | Nombre de la causa. |
| `descripcion` | `varchar(500)` | Nullable | Explicación de la causa. |
| `es_imputable` | `boolean` | Obligatorio | Indica si la causa es responsabilidad de la aerolínea. |

### `incidencia_vuelo`

Clasificación de negocio derivada de un evento operacional. Separa la causa original recibida de la causa normalizada usada para reglas y compensación.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_incidencia` | `bigint` | PK | Identificador de la incidencia. |
| `id_vuelo` | `bigint` | FK → `vuelo.id_vuelo` | Vuelo afectado. |
| `id_evento_origen` | `bigint` | FK único → `evento_operacional.id_evento` | Evento que originó la clasificación. |
| `id_causa` | `smallint` | FK → `causa.id_causa` | Causa normalizada. |
| `tipo` | `varchar(20)` | `RETRASO` o `CANCELACION` | Tipo de interrupción. |
| `minutos_retraso` | `integer` | Obligatorio para retraso | Minutos de retraso; es nulo en cancelaciones. |
| `es_causa_principal` | `boolean` | Por defecto `true` | Indica si es la causa principal. |
| `requiere_auditoria` | `boolean` | Por defecto `false` | Se activa para casos que deben revisarse. |
| `estado_revision` | `varchar(30)` | `PENDIENTE`, `APROBADA` o `RECHAZADA` | Resultado de la revisión. |
| `fecha_clasificacion_utc` | `timestamptz` | Obligatorio | Momento de la clasificación. |

Una incidencia con auditoría pendiente no puede generar una compensación.

### `auditoria_causa`

Evidencia de revisión para una causa técnica que coincide con clima severo, según RN-04.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_auditoria` | `bigint` | PK | Identificador de la auditoría. |
| `id_incidencia` | `bigint` | FK único → `incidencia_vuelo.id_incidencia` | Incidencia evaluada. |
| `id_observacion_clima_origen` | `bigint` | FK → `observacion_clima.id_observacion_clima`, nullable | Clima en el origen. |
| `id_observacion_clima_destino` | `bigint` | FK → `observacion_clima.id_observacion_clima`, nullable | Clima en el destino. |
| `motivo` | `varchar(500)` | Obligatorio | Razón de la auditoría. |
| `estado` | `varchar(30)` | `PENDIENTE`, `CONFIRMADA` o `DESCARTADA` | Estado de la auditoría. |
| `fecha_creacion_utc` | `timestamptz` | Obligatorio | Inicio de la auditoría. |
| `fecha_resolucion_utc` | `timestamptz` | Nullable | Momento de resolución. |

El trigger valida que el clima usado corresponda al origen o destino y esté a máximo una hora del evento.

### `regla_rotacion`

Catálogo versionado de tiempos mínimos de rotación de aeronaves. Sus valores iniciales son 45 minutos para vuelos nacionales y 60 para internacionales.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_regla_rotacion` | `smallint` | PK | Identificador de la regla. |
| `tipo_vuelo` | `varchar(20)` | `NACIONAL` o `INTERNACIONAL` | Clase del vuelo. |
| `minutos_minimos` | `integer` | Mayor que cero | Tiempo mínimo de rotación. |
| `vigente_desde_utc` | `timestamptz` | Obligatorio | Inicio de vigencia. |
| `vigente_hasta_utc` | `timestamptz` | Nullable | Fin de vigencia. |

### `proyeccion_propagacion`

Resultado de proyectar un retraso sobre el siguiente vuelo de la misma aeronave.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_proyeccion` | `bigint` | PK | Identificador de la proyección. |
| `id_vuelo_origen` | `bigint` | FK → `vuelo.id_vuelo` | Vuelo cuyo retraso se propaga. |
| `id_vuelo_afectado` | `bigint` | FK → `vuelo.id_vuelo` | Siguiente vuelo afectado. |
| `id_regla_rotacion` | `smallint` | FK → `regla_rotacion.id_regla_rotacion` | Regla de rotación usada. |
| `retraso_origen_min` | `integer` | No negativo | Retraso del vuelo origen. |
| `retraso_proyectado_min` | `integer` | No negativo | Retraso calculado para el vuelo afectado. |
| `fecha_calculo_utc` | `timestamptz` | Obligatorio | Momento de la proyección. |
| `estado` | `varchar(30)` | `PROYECTADA`, `CONFIRMADA` o `DESCARTADA` | Estado de la proyección. |

Un trigger comprueba que ambos vuelos pertenezcan a la misma aeronave y que el afectado sea el siguiente programado.

### `regla_compensacion`

Reglas de compensación versionadas. Los valores iniciales implementan RN-05: 25%, 50% y 100% según retraso; 100% más reubicación para cancelación imputable con aviso menor de 72 horas.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_regla_compensacion` | `smallint` | PK | Identificador de la regla. |
| `tipo_incidencia` | `varchar(20)` | `RETRASO` o `CANCELACION` | Tipo de interrupción al que aplica. |
| `minutos_minimos` | `integer` | Nullable en cancelación | Límite inferior inclusivo del retraso. |
| `minutos_maximos` | `integer` | Nullable | Límite superior exclusivo del retraso. |
| `aviso_max_horas` | `integer` | Solo cancelación | Máximo de horas de aviso para aplicar la regla. |
| `porcentaje` | `numeric(5,4)` | Entre 0 y 1 | Porcentaje de la tarifa a compensar. |
| `requiere_reubicacion` | `boolean` | Obligatorio | Indica si la regla exige reubicación. |
| `vigente_desde_utc` | `timestamptz` | Obligatorio | Inicio de vigencia. |
| `vigente_hasta_utc` | `timestamptz` | Nullable | Fin de vigencia. |

### `compensacion`

Compensación económica calculada para un pasajero y segmento afectado.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_compensacion` | `bigint` | PK | Identificador de la compensación. |
| `id_detalle_reserva` | `bigint` | FK único → `detalle_reserva.id_detalle_reserva` | Segmento y pasajero compensados. La unicidad implementa RN-09. |
| `id_incidencia` | `bigint` | FK → `incidencia_vuelo.id_incidencia` | Incidencia que la originó. |
| `id_regla_compensacion` | `smallint` | FK → `regla_compensacion.id_regla_compensacion` | Regla aplicada. |
| `minutos_imputables` | `integer` | Nullable, no negativo | Minutos usados para aplicar la regla. |
| `monto` | `numeric(12,2)` | No negativo | Monto calculado. |
| `moneda` | `varchar(3)` | Mayúsculas | Moneda de la tarifa y compensación. |
| `fecha_calculo_utc` | `timestamptz` | Obligatorio | Momento del cálculo. |
| `estado` | `varchar(30)` | Estado controlado | `CALCULADA`, `SOLICITADA`, `PAGADA`, `RECHAZADA` o `ANULADA`. |

El trigger verifica que el vuelo, causa imputable, regla, rango de retraso, vigencia, tarifa y monto sean coherentes.

### `pago`

Solicitud de pago enviada a F7. Una compensación tiene como máximo un pago.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_pago` | `bigint` | PK | Identificador interno del pago. |
| `id_compensacion` | `bigint` | FK único → `compensacion.id_compensacion` | Compensación a pagar. |
| `clave_idempotencia` | `varchar(150)` | Única | Clave enviada a F7 para evitar pagos duplicados. |
| `id_transaccion_externa` | `varchar(150)` | Único, nullable | Identificador devuelto por F7. |
| `estado` | `varchar(30)` | `PENDIENTE`, `PAGADO` o `RECHAZADO` | Estado actual de pago. |
| `fecha_solicitud_utc` | `timestamptz` | Obligatorio | Momento de la solicitud. |
| `fecha_actualizacion_utc` | `timestamptz` | Obligatorio | Última confirmación recibida. |

### `evento_pago`

Historial de respuestas asíncronas recibidas desde F7.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_evento_pago` | `bigint` | PK | Identificador interno del evento. |
| `id_pago` | `bigint` | FK → `pago.id_pago` | Pago actualizado. |
| `id_externo_evento` | `varchar(150)` | Único | Identificador idempotente de la confirmación externa. |
| `estado_reportado` | `varchar(30)` | Estado controlado | Estado reportado por F7. |
| `fecha_hora_evento_utc` | `timestamptz` | Obligatorio | Hora del evento en F7. |
| `fecha_hora_recepcion_utc` | `timestamptz` | Obligatorio | Hora de recepción en VuelaData. |

Un trigger actualiza el estado vigente de `pago` desde este historial.

### `reubicacion`

Gestión de una alternativa de viaje para un segmento afectado.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_reubicacion` | `bigint` | PK | Identificador de la gestión. |
| `id_detalle_reserva` | `bigint` | FK → `detalle_reserva.id_detalle_reserva` | Segmento del pasajero afectado. |
| `id_incidencia` | `bigint` | FK → `incidencia_vuelo.id_incidencia` | Incidencia que exige u origina la reubicación. |
| `id_vuelo_propuesto` | `bigint` | FK → `vuelo.id_vuelo`, nullable | Vuelo alternativo ofrecido. |
| `estado` | `varchar(30)` | Estado controlado | `PENDIENTE`, `OFRECIDA`, `ACEPTADA`, `RECHAZADA` o `COMPLETADA`. |
| `fecha_oferta_utc` | `timestamptz` | Nullable | Hora de la oferta al pasajero. |
| `fecha_respuesta_utc` | `timestamptz` | Nullable | Hora de la respuesta. |

El segmento y la incidencia deben pertenecer al mismo vuelo. Si una regla de compensación requiere reubicación, un trigger diferido exige que exista antes de confirmar la transacción.

### `notificacion`

Mensajes enviados o programados para el pasajero.

| Campo | Tipo | Clave / regla | Descripción |
|---|---|---|---|
| `id_notificacion` | `bigint` | PK | Identificador de la notificación. |
| `id_detalle_reserva` | `bigint` | FK → `detalle_reserva.id_detalle_reserva` | Segmento y pasajero destinatario. |
| `id_evaluacion_conexion` | `bigint` | FK → `evaluacion_conexion.id_evaluacion`, nullable | Evaluación que originó una alerta de conexión. |
| `id_compensacion` | `bigint` | FK → `compensacion.id_compensacion`, nullable | Compensación comunicada. |
| `tipo` | `varchar(30)` | Tipo controlado | `CONEXION_RIESGO`, `COMPENSACION`, `REUBICACION` o `INTERRUPCION`. |
| `canal` | `varchar(20)` | `EMAIL`, `SMS` o `PUSH` | Medio de entrega. |
| `estado_envio` | `varchar(30)` | `PENDIENTE`, `ENVIADA` o `FALLIDA` | Estado de entrega. |
| `fecha_programada_utc` | `timestamptz` | Obligatorio | Momento previsto de envío. |
| `fecha_envio_utc` | `timestamptz` | Nullable | Momento real de envío. |

Un trigger comprueba que una notificación de conexión corresponda a una evaluación en riesgo o perdida del mismo itinerario, y que una notificación de compensación corresponda al mismo segmento.

## Reglas de integridad implementadas

| Regla | Implementación |
|---|---|
| RN-01: OTP con llegada real a puerta | `vuelo.llegada_real_puerta_utc` conserva el evento `IN` para calcular el retraso frente a `llegada_programada_utc`. |
| RN-02: tiempos en UTC | Todos los instantes operacionales usan `timestamptz` y el nombre termina en `_utc`. |
| RN-03: causas imputables | `causa.es_imputable` determina si una incidencia puede compensarse. |
| RN-04: auditoría por clima | `auditoria_causa` enlaza la incidencia con observaciones de clima válidas de origen o destino. |
| RN-05: escala de compensación | `regla_compensacion` y el trigger de `compensacion` validan porcentajes, rangos y vigencia. |
| RN-06: causa no imputable | El trigger rechaza compensaciones económicas si `es_imputable = false`; pueden emitirse notificaciones y reubicaciones. |
| RN-07: conexión en riesgo | `conexion_itinerario`, `tiempo_minimo_conexion` y `evaluacion_conexion` registran el cálculo. |
| RN-08: propagación | `proyeccion_propagacion` y `regla_rotacion` modelan el retraso entre vuelos consecutivos de la misma aeronave. |
| RN-09: pago único | `compensacion.id_detalle_reserva`, `pago.id_compensacion` y claves idempotentes son únicas. |
| RN-10: vuelos desviados | `vuelo.id_aeropuerto_desvio` y el estado `DESVIADO` permiten excluirlos de OTP y reportarlos aparte. |
| RN-11: aislamiento de pasajero | La ruta `pasajero → reserva_pasajero → itinerario → detalle_reserva` permite aplicar autorización en la API. |
