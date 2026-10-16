
import pandas as pd
import numpy as np
from pathlib import Path


# ============================================================
# 1. RUTAS Y CONFIGURACION
# ============================================================

BASE_DIR = Path(__file__).resolve().parent
REFERENCE_DIR = BASE_DIR.parent / "reference"
OUTPUT_DIR = BASE_DIR / "output"

AIRPORTS_FILE = REFERENCE_DIR / "airports.csv"

NUM_AIRCRAFT = 30
NUM_FLIGHTS = 2700

AVERAGE_SPEED_KMH = 750
ADDITIONAL_FLIGHT_MINUTES = 30
TURNAROUND_MINUTES = 45

WEEK_START_DATE = "2026-10-19"

RANDOM_SEED = 42


# ============================================================
# 2. CARGAR LOS AEROPUERTOS
# ============================================================

airports = pd.read_csv(AIRPORTS_FILE)

print("Aeropuertos cargados:", len(airports))


# ============================================================
# 3. LIMPIAR Y VALIDAR LOS AEROPUERTOS
# ============================================================

airports["LATITUDE"] = pd.to_numeric(
    airports["LATITUDE"],
    errors="coerce"
)

airports["LONGITUDE"] = pd.to_numeric(
    airports["LONGITUDE"],
    errors="coerce"
)

airports = airports.dropna(
    subset=["IATA_CODE", "LATITUDE", "LONGITUDE"]
).copy()

airports = airports[
    airports["LATITUDE"].between(-90, 90)
    & airports["LONGITUDE"].between(-180, 180)
].copy()

airports = airports.drop_duplicates(
    subset=["IATA_CODE"]
).reset_index(drop=True)

if len(airports) < 3:
    raise ValueError(
        "No hay suficientes aeropuertos válidos para generar rutas."
    )

print("Aeropuertos disponibles:", len(airports))


# ============================================================
# 4. CALCULAR DISTANCIAS
# ============================================================

def calcular_distancia(origen, destino):

    lat1 = np.radians(origen["LATITUDE"])
    lon1 = np.radians(origen["LONGITUDE"])

    lat2 = np.radians(destino["LATITUDE"])
    lon2 = np.radians(destino["LONGITUDE"])

    diferencia_lat = lat2 - lat1
    diferencia_lon = lon2 - lon1

    a = (
        np.sin(diferencia_lat / 2) ** 2
        + np.cos(lat1)
        * np.cos(lat2)
        * np.sin(diferencia_lon / 2) ** 2
    )

    a = np.clip(a, 0, 1)

    distancia = 2 * 6371 * np.arcsin(np.sqrt(a))

    return distancia


# ============================================================
# 5. ESTIMAR DURACION DEL VUELO
# ============================================================

def estimar_duracion(distancia):

    duracion = (
        distancia / AVERAGE_SPEED_KMH * 60
        + ADDITIONAL_FLIGHT_MINUTES
    )

    return int(np.ceil(duracion))


# ============================================================
# 6. GENERAR RUTAS PARA TODOS LOS AEROPUERTOS
# ============================================================

# Cada aeropuerto se conecta con sus 3 aeropuertos más cercanos.
# No se excluyen aeropuertos por su ubicación o distancia.

connections = []

for i in range(len(airports)):

    origin = airports.iloc[i]
    distances = []

    for j in range(len(airports)):

        if i == j:
            continue

        destination = airports.iloc[j]

        distance = calcular_distancia(
            origin,
            destination
        )

        distances.append({
            "origin_airport": origin["IATA_CODE"],
            "destination_airport": destination["IATA_CODE"],
            "distance_km": round(distance, 2)
        })

    nearest_airports = sorted(
        distances,
        key=lambda route: route["distance_km"]
    )[:3]

    connections.extend(nearest_airports)


routes = pd.DataFrame(connections)

# Evitar duplicar una conexión cuando ya existe en sentido contrario.

routes["route_key"] = routes.apply(
    lambda route: tuple(sorted([
        route["origin_airport"],
        route["destination_airport"]
    ])),
    axis=1
)

routes = routes.drop_duplicates(
    subset=["route_key"]
).drop(columns=["route_key"])

# Crear las rutas de regreso.

reverse_routes = routes.rename(columns={
    "origin_airport": "destination_airport",
    "destination_airport": "origin_airport"
})

routes = pd.concat(
    [routes, reverse_routes],
    ignore_index=True
)

routes = routes.drop_duplicates(
    subset=["origin_airport", "destination_airport"]
).reset_index(drop=True)

routes["estimated_duration_minutes"] = routes[
    "distance_km"
].apply(estimar_duracion)

print("\n========== RED DE RUTAS ==========")
print("Aeropuertos disponibles:", len(airports))
print("Rutas dirigidas:", len(routes))
print("Distancia mínima:", routes["distance_km"].min(), "km")
print("Distancia máxima:", routes["distance_km"].max(), "km")


# ============================================================
# 7. CREAR LA FLOTA SINTETICA
# ============================================================

fleet = pd.DataFrame({
    "aircraft_registration": [
        f"SIM-{i:03d}"
        for i in range(1, NUM_AIRCRAFT + 1)
    ]
})

print("\n========== FLOTA SINTETICA ==========")
print(fleet.to_string(index=False))
print("Total de aeronaves:", len(fleet))


# ============================================================
# 8. PREPARAR LAS RUTAS DE SALIDA
# ============================================================

outgoing_routes = {}

for _, route in routes.iterrows():

    origin = route["origin_airport"]

    outgoing_routes.setdefault(origin, []).append(
        route.to_dict()
    )


# ============================================================
# 9. SELECCIONAR LOS AEROPUERTOS INICIALES
# ============================================================

airport_distances = []

for airport_code, airport_routes in outgoing_routes.items():

    shortest_flight = min(
        route["estimated_duration_minutes"]
        for route in airport_routes
    )

    airport_distances.append({
        "airport": airport_code,
        "shortest_flight": shortest_flight
    })

airport_distances = pd.DataFrame(airport_distances)

airport_distances = airport_distances.sort_values(
    "shortest_flight"
).reset_index(drop=True)

starting_airports = airport_distances.head(
    NUM_AIRCRAFT
)["airport"].tolist()

# Si hay menos de 30 aeropuertos de salida,
# repetirlos para asignar una ubicación inicial a cada aeronave.

while len(starting_airports) < NUM_AIRCRAFT:

    starting_airports.extend(
        airport_distances["airport"].tolist()
    )

starting_airports = starting_airports[:NUM_AIRCRAFT]


# ============================================================
# 10. INICIALIZAR LA DISPONIBILIDAD DE LAS AERONAVES
# ============================================================

rng = np.random.default_rng(RANDOM_SEED)

week_start = pd.Timestamp(WEEK_START_DATE)
week_end = week_start + pd.Timedelta(days=7)

aircraft_state = []

for i in range(NUM_AIRCRAFT):

    aircraft_state.append({
        "registration": fleet.iloc[i][
            "aircraft_registration"
        ],
        "current_airport": starting_airports[i],
        "next_departure": week_start + pd.Timedelta(
            hours=5 + i % 4
        )
    })


# ============================================================
# 11. GENERAR EL ITINERARIO SEMANAL
# ============================================================

flights = []
flight_number = 1

while flight_number <= NUM_FLIGHTS:

    # Seleccionar la aeronave disponible más temprano.

    aircraft_state.sort(
        key=lambda item: item["next_departure"]
    )

    aircraft = aircraft_state[0]

    departure_time = aircraft["next_departure"]
    current_airport = aircraft["current_airport"]

    if departure_time >= week_end:

        raise ValueError(
            f"No fue posible programar los {NUM_FLIGHTS} vuelos "
            "dentro de la semana. La capacidad de la flota "
            "es insuficiente con los parámetros actuales."
        )

    available_routes = outgoing_routes.get(
        current_airport,
        []
    )

    if not available_routes:

        raise ValueError(
            f"No hay rutas de salida desde {current_airport}."
        )

    # CAMBIO PRINCIPAL:
    # seleccionar entre TODAS las rutas disponibles,
    # no solamente entre las tres rutas más cortas.

    route_index = int(
        rng.integers(0, len(available_routes))
    )

    route = available_routes[route_index]

    duration = int(
        route["estimated_duration_minutes"]
    )

    arrival_time = departure_time + pd.Timedelta(
        minutes=duration
    )

    if arrival_time >= week_end:

        aircraft["next_departure"] = week_end
        continue

    flights.append({
        "flight_id": f"SIM-FLT-{flight_number:05d}",
        "flight_date": departure_time.date(),
        "origin_airport": route["origin_airport"],
        "destination_airport": route["destination_airport"],
        "aircraft_registration": aircraft["registration"],
        "scheduled_departure": departure_time,
        "scheduled_arrival": arrival_time,
        "distance_km": route["distance_km"],
        "scheduled_duration_minutes": duration
    })

    flight_number += 1

    # Actualizar ubicación y disponibilidad.

    aircraft["current_airport"] = route["destination_airport"]

    aircraft["next_departure"] = (
        arrival_time
        + pd.Timedelta(minutes=TURNAROUND_MINUTES)
    )


flights = pd.DataFrame(flights)

flights = flights.sort_values(
    "scheduled_departure"
).reset_index(drop=True)


# ============================================================
# 12. REVISAR DISTANCIAS Y DURACIONES
# ============================================================

print("\n========== DISTANCIAS DEL ITINERARIO ==========")

print("Distancia mínima:", flights["distance_km"].min(), "km")
print("Distancia máxima:", flights["distance_km"].max(), "km")
print(
    "Distancia promedio:",
    round(flights["distance_km"].mean(), 2),
    "km"
)

print(
    "Duración mínima:",
    flights["scheduled_duration_minutes"].min(),
    "minutos"
)

print(
    "Duración máxima:",
    flights["scheduled_duration_minutes"].max(),
    "minutos"
)

print("\nVuelos más largos:")

print(
    flights.nlargest(10, "distance_km")[
        [
            "origin_airport",
            "destination_airport",
            "distance_km",
            "scheduled_duration_minutes"
        ]
    ].to_string(index=False)
)


# ============================================================
# 13. VALIDAR EL ITINERARIO
# ============================================================

print("\n========== VALIDACION DEL ITINERARIO ==========")

print("Total de vuelos:", len(flights))

print(
    "Aeronaves utilizadas:",
    flights["aircraft_registration"].nunique()
)

print(
    "Aeropuertos utilizados en vuelos:",
    len(
        set(flights["origin_airport"])
        | set(flights["destination_airport"])
    )
)

print(
    "Vuelos fuera de la semana:",
    (flights["scheduled_arrival"] >= week_end).sum()
)

# Revisar las rotaciones de cada aeronave.

flights = flights.sort_values(
    ["aircraft_registration", "scheduled_departure"]
).reset_index(drop=True)

flights["previous_arrival"] = (
    flights.groupby("aircraft_registration")["scheduled_arrival"]
    .shift(1)
)

flights["previous_destination"] = (
    flights.groupby("aircraft_registration")["destination_airport"]
    .shift(1)
)

overlapping_flights = flights[
    flights["previous_arrival"].notna()
    & (
        flights["scheduled_departure"]
        < flights["previous_arrival"]
    )
]

disconnected_flights = flights[
    flights["previous_destination"].notna()
    & (
        flights["origin_airport"]
        != flights["previous_destination"]
    )
]

turnaround_violations = flights[
    flights["previous_arrival"].notna()
    & (
        flights["scheduled_departure"]
        < flights["previous_arrival"]
        + pd.Timedelta(minutes=TURNAROUND_MINUTES)
    )
]

print("Vuelos superpuestos:", len(overlapping_flights))
print("Saltos de aeropuerto:", len(disconnected_flights))
print(
    "Incumplimientos del tiempo en tierra:",
    len(turnaround_violations)
)

if (
    len(flights) != NUM_FLIGHTS
    or len(overlapping_flights) > 0
    or len(disconnected_flights) > 0
    or len(turnaround_violations) > 0
    or (flights["scheduled_arrival"] >= week_end).any()
):
    raise ValueError(
        "El itinerario no superó todas las validaciones."
    )

print("Todas las validaciones finalizaron correctamente.")


# ============================================================
# 14. GUARDAR LOS CSV
# ============================================================

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

routes.to_csv(
    OUTPUT_DIR / "synthetic_routes.csv",
    index=False
)

fleet.to_csv(
    OUTPUT_DIR / "synthetic_fleet.csv",
    index=False
)

flights = flights.drop(
    columns=[
        "previous_arrival",
        "previous_destination"
    ]
)

flights.to_csv(
    OUTPUT_DIR / "synthetic_weekly_itinerary.csv",
    index=False
)

print("\nArchivos generados correctamente:")
print(OUTPUT_DIR / "synthetic_routes.csv")
print(OUTPUT_DIR / "synthetic_fleet.csv")
print(OUTPUT_DIR / "synthetic_weekly_itinerary.csv")
