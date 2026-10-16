
# VuelaData — Generador de Itinerario y Rotación de Flota

## Descripción

Este repositorio contiene un generador de datos sintéticos para el módulo de **itinerario y rotación de flota de VuelaData**.

El objetivo es generar una programación semanal de vuelos a partir de un catálogo de aeropuertos, calcular distancias y duraciones estimadas, crear matrículas ficticias para las aeronaves y asignarlas a vuelos programados.

Los datos generados sirven como fuente de información para simular operaciones aéreas, analizar itinerarios y apoyar el desarrollo de los componentes de procesamiento y análisis de datos del proyecto.

## Objetivos

- Utilizar los aeropuertos disponibles en el catálogo de referencia que tengan coordenadas geográficas válidas.
- Calcular distancias entre aeropuertos mediante sus coordenadas.
- Generar rutas sintéticas de ida y vuelta.
- Crear identificadores ficticios para las aeronaves.
- Generar un itinerario semanal con vuelos asignados a las aeronaves.
- Validar la continuidad de las rotaciones y la disponibilidad temporal de la flota.
- Exportar los resultados en archivos CSV para su posterior integración en el ecosistema de VuelaData.

## Tecnologías utilizadas

- **Python:** lenguaje utilizado para implementar el generador.
- **Pandas:** carga, limpieza, transformación y exportación de datos tabulares.
- **NumPy:** cálculos numéricos y generación reproducible de valores aleatorios.
- **CSV:** formato utilizado para los catálogos de entrada y los archivos generados.
- **uv:** gestión de dependencias y ejecución del proyecto.

## Estructura del repositorio

```text
data-sources/
├── reference/
│   ├── airports.csv
│   └── airlines.csv
│
└── fleet_itinerary/
    ├── generate_fleet_itinerary.py
    ├── pyproject.toml
    ├── uv.lock
    └── output/
        ├── synthetic_routes.csv
        ├── synthetic_fleet.csv
        └── synthetic_weekly_itinerary.csv
```

Los archivos `pyproject.toml` y `uv.lock` corresponden a la configuración y las dependencias del proyecto administradas con `uv`.

El catálogo `airports.csv` se utiliza como fuente de aeropuertos. El catálogo `airlines.csv` está disponible como referencia, aunque el generador actual de itinerarios no necesita utilizarlo directamente.

## Fuente de datos

### `airports.csv`

Contiene el catálogo de aeropuertos utilizado para construir la red de rutas.

Entre sus columnas se encuentran:

| Columna       | Descripción                     |
| ------------- | -------------------------------- |
| `IATA_CODE` | Código IATA del aeropuerto.     |
| `AIRPORT`   | Nombre del aeropuerto.           |
| `CITY`      | Ciudad donde se encuentra.       |
| `STATE`     | Estado o región administrativa. |
| `COUNTRY`   | País.                           |
| `LATITUDE`  | Latitud geográfica.             |
| `LONGITUDE` | Longitud geográfica.            |

El proceso convierte las coordenadas a valores numéricos, elimina registros sin coordenadas válidas y elimina códigos IATA duplicados.

En las ejecuciones realizadas, el catálogo contiene 322 registros y se obtienen 319 aeropuertos con coordenadas válidas.

## Funcionamiento del generador

El archivo principal es `generate_fleet_itinerary.py`.

### 1. Carga y limpieza de datos

Se carga el catálogo de aeropuertos y se validan las coordenadas geográficas.

Se conservan los aeropuertos que cuentan con código IATA y coordenadas válidas, sin filtrar por estado o por distancia máxima.

### 2. Cálculo de distancias

Se implementa una función basada en la fórmula de Haversine para calcular la distancia geográfica entre dos aeropuertos a partir de sus coordenadas.

Las distancias se expresan en kilómetros.

### 3. Estimación de duración

La duración estimada de cada vuelo se calcula utilizando una velocidad promedio configurable y un tiempo adicional fijo.

La fórmula implementada es:

```text
Duración estimada (minutos) =
    (Distancia en km / Velocidad promedio en km/h) × 60
    + Minutos adicionales
```

La configuración actual utiliza:

- Velocidad promedio: 750 km/h.
- Tiempo adicional: 30 minutos.

Estos valores son parámetros sintéticos para la simulación y no representan necesariamente la duración real de un vuelo comercial.

### 4. Generación de rutas

Se construye una red sintética de conexiones entre aeropuertos.

El algoritmo identifica los tres aeropuertos más cercanos a cada aeropuerto del catálogo y genera conexiones de ida y vuelta. Las rutas se consolidan para evitar duplicados.

No se establece un límite máximo de distancia para excluir aeropuertos o conexiones.

### 5. Generación de la flota

Se crean 30 matrículas ficticias con identificadores consecutivos:

```text
SIM-001
SIM-002
SIM-003
...
SIM-030
```

Estas matrículas permiten identificar las aeronaves asignadas a los vuelos del itinerario.

### 6. Generación del itinerario semanal

Se genera una programación sintética con un objetivo de 2.700 vuelos durante siete días.

Cada vuelo incluye un identificador, aeropuerto de origen, aeropuerto de destino, matrícula asignada, hora programada de salida, hora estimada de llegada, distancia y duración estimada.

La programación utiliza una semilla aleatoria fija para favorecer la reproducibilidad de los resultados.

La aeronave seleccionada debe encontrarse en el aeropuerto de origen del vuelo y disponer de tiempo suficiente desde su operación anterior. Se consideran 45 minutos de tiempo en tierra entre vuelos consecutivos.

### 7. Validación

El proceso incorpora comprobaciones para detectar:

- Vuelos que excedan el período semanal.
- Vuelos superpuestos para una misma aeronave.
- Inconsistencias entre el destino de un vuelo y el origen del siguiente.
- Incumplimientos del tiempo mínimo en tierra.
- Diferencias entre la cantidad de vuelos esperada y la generada.

Si las condiciones de programación no permiten completar el itinerario, el proceso debe informar el error en lugar de considerar válida una programación incompleta.

## Archivos de salida

Los resultados se almacenan en la carpeta `output/`.

### `synthetic_routes.csv`

Contiene las conexiones de la red sintética.

| Columna                        | Descripción                                |
| ------------------------------ | ------------------------------------------- |
| `origin_airport`             | Código IATA del aeropuerto de origen.      |
| `destination_airport`        | Código IATA del aeropuerto de destino.     |
| `distance_km`                | Distancia estimada en kilómetros.          |
| `estimated_duration_minutes` | Duración estimada del trayecto en minutos. |

### `synthetic_fleet.csv`

Contiene el catálogo de aeronaves sintéticas.

| Columna                   | Descripción                        |
| ------------------------- | ----------------------------------- |
| `aircraft_registration` | Matrícula ficticia de la aeronave. |

### `synthetic_weekly_itinerary.csv`

Contiene la programación semanal de vuelos.

| Columna                        | Descripción                               |
| ------------------------------ | ------------------------------------------ |
| `flight_id`                  | Identificador único del vuelo sintético. |
| `flight_date`                | Fecha programada del vuelo.                |
| `origin_airport`             | Aeropuerto de origen.                      |
| `destination_airport`        | Aeropuerto de destino.                     |
| `aircraft_registration`      | Matrícula asignada.                       |
| `scheduled_departure`        | Fecha y hora programadas de salida.        |
| `scheduled_arrival`          | Fecha y hora estimadas de llegada.         |
| `distance_km`                | Distancia geográfica estimada.            |
| `scheduled_duration_minutes` | Duración estimada en minutos.             |

Los archivos son generados por el script. No se crea un CSV adicional de aeropuertos.

## Instalación y ejecución

### Requisitos previos

- Python compatible con las dependencias del proyecto.
- `uv` instalado.
- Catálogo `airports.csv` disponible en `data-sources/reference/`.

### Instalar dependencias

Desde la carpeta `fleet_itinerary`, si todavía no están instaladas:

```powershell
uv sync
```

### Ejecutar el generador

```powershell
uv run python generate_fleet_itinerary.py
```

El script muestra en consola información sobre los aeropuertos disponibles, las rutas generadas, la flota y las validaciones del itinerario.

Los archivos CSV se guardan en `output/`.

## Consideraciones

- Los vuelos, las matrículas y las programaciones son sintéticos.
- Las distancias se calculan geográficamente; no corresponden necesariamente a rutas comerciales operadas.
- La duración estimada utiliza parámetros simplificados y no incorpora todas las variables de una operación aérea real.
- Que un aeropuerto forme parte de la red no garantiza que aparezca en el itinerario semanal generado.
- La cantidad de vuelos que puede programarse depende de las distancias, las duraciones, el tiempo en tierra y la disponibilidad de las aeronaves.

## Contexto dentro de VuelaData

Este generador forma parte del componente de fuentes de datos sintéticas de VuelaData. Su función es proporcionar información operacional simulada que pueda utilizarse en las siguientes etapas del proyecto, como la persistencia de datos, la simulación de eventos de vuelo y los procesos de integración y análisis.

El itinerario generado constituye una programación prevista; los eventos operacionales reales o simulados, como salida de puerta, despegue, aterrizaje y llegada a puerta, corresponden a procesos posteriores del sistema.
