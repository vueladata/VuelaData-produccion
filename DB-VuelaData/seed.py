import os
import random
import argparse
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv
import pandas as pd
from faker import Faker
from datetime import timedelta


# 1. Cargar variables de entorno de forma segura
load_dotenv()
fake = Faker()

def configurar_semillas(semilla=42):
    """Fija la semilla para garantizar la reproducibilidad de los datos."""
    Faker.seed(semilla)
    random.seed(semilla)
    print(f"[*] Semilla fijada en: {semilla}")

def obtener_conexion():
    """Establece la conexión a PostgreSQL usando variables de entorno (sin hardcodear)."""
    try:
        conn = psycopg2.connect(
            host=os.getenv("DB_HOST"),
            port=os.getenv("DB_PORT"),
            dbname=os.getenv("DB_NAME"),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD")
        )

        with conn.cursor() as cur:
            cur.execute("SET search_path TO vueladata, public;")
        return conn
    except Exception as e:
        print(f"[!] Error conectando a la base de datos: {e}")
        exit(1)

def insertar_lote_idempotente(conn, tabla, columnas, datos, conflicto_pk):
    """
    Función maestra para la idempotencia. 
    Inserta un lote de datos y usa ON CONFLICT DO NOTHING.
    - tabla: Nombre de la tabla 
    - columnas: Lista de columnas 
    - datos: Lista de tuplas con los valores.
    - conflicto_pk: La columna que es UNIQUE o PRIMARY KEY en la BD para evitar duplicados.
    """
    if not datos:
        return

    cols_str = ",".join(columnas)
    # Genera los placeholders (%s, %s...)
    vals_str = ",".join(["%s"] * len(columnas)) 
    
    query = f"""
        INSERT INTO {tabla} ({cols_str}) 
        VALUES %s 
        ON CONFLICT ({conflicto_pk}) DO NOTHING;
    """
    
    with conn.cursor() as cur:
        # execute_values es altamente eficiente para insertar miles de registros de golpe
        execute_values(cur, query, datos, template=f"({vals_str})")
        print(f"[*] Lote procesado en la tabla '{tabla}'.")

# FUNCIONES DE INSERCIÓN POR NIVELES

def insertar_nivel_1_catalogos(conn):
    """Inserta catálogos base que no dependen de nadie: pais, aerolinea, estado_vuelo, causa."""
    print("--- Procesando Nivel 1: Catálogos Base ---")
    
    # 1. Tabla 'pais' 
    datos_pais = [("United States", "USA")]
    insertar_lote_idempotente(conn, "pais", ["nombre", "codigo_iso"], datos_pais, "codigo_iso")

    # 2. Tabla 'aerolinea' (Desde tu CSV)
    try:
        csv_aerolineas = pd.read_csv("airlines.csv")
        datos_aerolineas = list(csv_aerolineas[['IATA_CODE', 'AIRLINE']].itertuples(index=False, name=None))
        insertar_lote_idempotente(conn, "aerolinea", ["codigo_iata", "nombre"], datos_aerolineas, "codigo_iata")
    except FileNotFoundError:
        print("[!] No se encontró airlines.csv. Asegúrate de tenerlo en la misma ruta del script.")

    # 3. Tabla 'estado_vuelo'
    datos_estado = [
        ('PROGRAMADO', 'Programado', 'Vuelo programado sin evento operacional confirmado'),
        ('SALIDA_PUERTA', 'Salida de puerta', 'Evento OUT recibido'),
        ('DESPEGADO', 'Despegado', 'Evento OFF recibido'),
        ('ATERRIZADO', 'Aterrizado', 'Evento ON recibido'),
        ('LLEGADA_PUERTA', 'Llegada a puerta', 'Evento IN recibido'),
        ('CANCELADO', 'Cancelado', 'Vuelo cancelado'),
        ('DESVIADO', 'Desviado', 'Vuelo desviado a un aeropuerto alterno')
    ]
    insertar_lote_idempotente(conn, "estado_vuelo", ["codigo", "nombre", "descripcion"], datos_estado, "codigo")

    # 4. Tabla 'causa'
    datos_causa = [
        ('TECNICA', 'Técnica', 'Falla o mantenimiento técnico atribuible a la aerolínea', True),
        ('TRIPULACION', 'Tripulación', 'Indisponibilidad o demora de la tripulación', True),
        ('AERONAVE_ANTERIOR', 'Aeronave anterior', 'Propagación desde una operación anterior imputable', True),
        ('CLIMA', 'Clima', 'Condición meteorológica adversa', False),
        ('ATC', 'Control de tráfico aéreo', 'Restricción de control de tráfico aéreo', False),
        ('SEGURIDAD', 'Seguridad', 'Evento de seguridad', False)
    ]
    insertar_lote_idempotente(conn, "causa", ["codigo", "nombre", "descripcion", "es_imputable"], datos_causa, "codigo")

def obtener_diccionario_ids(conn, query, llave_col, valor_col, params=None):
    """Función de ayuda para traer diccionarios de IDs (ej. nombre_ciudad -> id_ciudad)."""
    with conn.cursor() as cur:
        if params:
            cur.execute(query, params)
        else:
            cur.execute(query)
        resultados = cur.fetchall()
        return {fila[0]: fila[1] for fila in resultados}

def insertar_nivel_2_y_3_geografia_y_flota(conn):
    print("--- Procesando Niveles 2 y 3: Geografía y Flota ---")

    try:
        csv_aeropuertos = pd.read_csv("airports.csv")
    except FileNotFoundError:
        print("[!] No se encontró airports.csv. Asegúrate de tenerlo en la ruta correcta.")
        return

    # 1. Tabla 'ciudad'
    # Obtenemos el ID del país USA insertado en el Nivel 1
    with conn.cursor() as cur:
        cur.execute("SELECT id_pais FROM pais WHERE codigo_iso = 'USA'")
        id_pais_usa = cur.fetchone()[0]

    # Extraemos ciudades únicas del CSV
    ciudades_unicas = csv_aeropuertos['CITY'].dropna().unique()

    # Preparamos los datos: (id_pais, nombre)
    datos_ciudades = [(id_pais_usa, ciudad) for ciudad in ciudades_unicas]

    # El conflicto aquí se basa en la combinación única definida en el esquema (id_pais, nombre)
    insertar_lote_idempotente(conn, "ciudad", ["id_pais", "nombre"], datos_ciudades, "id_pais, nombre")


    # 2. Tabla 'aeropuerto'
    # Traemos el diccionario de ciudades: {'New York': 1, 'Los Angeles': 2, ...}
    dic_ciudades = obtener_diccionario_ids(conn, "SELECT nombre, id_ciudad FROM ciudad WHERE id_pais = %s", "nombre", "id_ciudad", (id_pais_usa,))
    csv_aeropuertos = csv_aeropuertos.dropna(subset=['LATITUDE', 'LONGITUDE'])

    datos_aeropuertos = []
    for _, fila in csv_aeropuertos.iterrows():
        nombre_ciudad = fila['CITY']
        id_ciudad = dic_ciudades.get(nombre_ciudad)

        if id_ciudad:
            datos_aeropuertos.append((
                id_ciudad,
                fila['IATA_CODE'],
                fila['AIRPORT'],
                float(fila['LATITUDE']),
                float(fila['LONGITUDE']),
                "America/New_York", # Inventamos la zona horaria porque tu CSV no la trae
                False 
            ))

    insertar_lote_idempotente(
        conn, 
        "aeropuerto", 
        ["id_ciudad", "codigo_iata", "nombre", "latitud", "longitud", "zona_horaria", "es_hub"], 
        datos_aeropuertos, 
        "codigo_iata"
    )

    # 3. Tabla 'aeronave'
    dic_aerolineas = obtener_diccionario_ids(conn, "SELECT codigo_iata, id_aerolinea FROM aerolinea", "codigo_iata", "id_aerolinea")
    lista_ids_aerolineas = list(dic_aerolineas.values())

    if not lista_ids_aerolineas:
        print("[!] No hay aerolíneas en la BD. No se pueden generar aeronaves.")
        return

    # Generamos 50 aviones de forma reproducible
    modelos_aviones = ["Boeing 737", "Airbus A320", "Embraer 190", "Boeing 787", "Airbus A350"]
    datos_aeronaves = []

    for _ in range(50):
        # La matrícula en el formato de aviación de USA empieza por N
        matricula = f"N{fake.random_int(min=100, max=999)}{fake.random_uppercase_letter()}{fake.random_uppercase_letter()}"
        id_aerolinea = random.choice(lista_ids_aerolineas)
        modelo = random.choice(modelos_aviones)
        capacidad = random.randint(100, 250)

        datos_aeronaves.append((
            id_aerolinea,
            matricula,
            modelo,
            capacidad,
            'DISPONIBLE' 
        ))

    insertar_lote_idempotente(conn, 
        "aeronave", 
        ["id_aerolinea", "matricula", "modelo", "capacidad_pasajeros", "estado_operativo"], 
        datos_aeronaves, 
        "matricula"
    )

def insertar_nivel_4_geometria(conn):
    print("--- Procesando Nivel 4: Geometría del Negocio ---")

    dic_aeropuertos = obtener_diccionario_ids(conn, "SELECT codigo_iata, id_aeropuerto FROM aeropuerto", "codigo_iata", "id_aeropuerto")
    lista_ids_aeropuertos = list(dic_aeropuertos.values())

    if len(lista_ids_aeropuertos) < 2:
        print("[!] No hay suficientes aeropuertos para crear rutas.")
        return

    # 1. Tabla 'ruta'
    datos_rutas = []
    rutas_creadas = set()

    while len(datos_rutas) < 100:
        origen = random.choice(lista_ids_aeropuertos)
        destino = random.choice(lista_ids_aeropuertos)

        if origen != destino and (origen, destino) not in rutas_creadas:
            duracion = random.randint(45, 300)
            datos_rutas.append((origen, destino, duracion))
            rutas_creadas.add((origen, destino))

    insertar_lote_idempotente(
        conn,
        "ruta",
        ["id_aeropuerto_origen", "id_aeropuerto_destino", "duracion_estimada_min"],
        datos_rutas,
        "id_aeropuerto_origen, id_aeropuerto_destino"
    )

    # 2. Tabla 'tiempo_minimo_conexion'
    # Seleccionamos 5 aeropuertos al azar para simular que son hubs con reglas de conexión
    hubs = random.sample(lista_ids_aeropuertos, 5)
    datos_conexion = []
    fecha_vigencia = "2020-01-01T00:00:00Z"

    for id_hub in hubs:
        datos_conexion.extend([
            (id_hub, 'NACIONAL', 'NACIONAL', 45, fecha_vigencia),
            (id_hub, 'NACIONAL', 'INTERNACIONAL', 60, fecha_vigencia),
            (id_hub, 'INTERNACIONAL', 'NACIONAL', 90, fecha_vigencia),
            (id_hub, 'INTERNACIONAL', 'INTERNACIONAL', 120, fecha_vigencia)
        ])

    insertar_lote_idempotente(
        conn,
        "tiempo_minimo_conexion",
        ["id_aeropuerto", "tipo_llegada", "tipo_salida", "minutos_minimos", "vigente_desde_utc"],
        datos_conexion,
        "id_aeropuerto, tipo_llegada, tipo_salida, vigente_desde_utc"
    )

def insertar_nivel_5_y_6_transaccional(conn, args):
    print("--- Procesando Niveles 5 y 6: Pasajeros, Reservas y Vuelos ---")

    # Control de volumen según parámetro CLI
    cantidad_base = 10 if args.volumen == "small" else 1000

    # 1. Tabla 'pasajero'
    datos_pasajeros = []
    documentos_creados = set()
    cantidad_pasajeros = cantidad_base * 5 
    
    while len(datos_pasajeros) < cantidad_pasajeros:
        tipo_doc = random.choice(['PASAPORTE', 'DNI', 'CEDULA'])
        documento = str(fake.random_number(digits=10, fix_len=True))
        
        if (tipo_doc, documento) not in documentos_creados:
            datos_pasajeros.append((
                fake.first_name(),
                fake.last_name(),
                documento,
                tipo_doc,
                fake.date_of_birth(minimum_age=1, maximum_age=90),
                fake.email(),
                fake.phone_number()
            ))
            documentos_creados.add((tipo_doc, documento))
            
    insertar_lote_idempotente(
        conn,
        "pasajero",
        ["nombre", "apellido", "documento", "tipo_documento", "fecha_nacimiento", "correo", "telefono"],
        datos_pasajeros,
        "tipo_documento, documento"
    )

    # 2. Tabla 'reserva'
    datos_reservas = []
    codigos_reserva_creados = set()
    cantidad_reservas = cantidad_base * 2

    while len(datos_reservas) < cantidad_reservas:
        codigo = fake.bothify('??####', letters='ABCDEFGHIJKLMNOPQRSTUVWXYZ')

        if codigo not in codigos_reserva_creados:
            fecha_reserva = fake.date_time_this_year()
            datos_reservas.append((
                codigo,
                fecha_reserva,
                'CONFIRMADA',
                fecha_reserva
            ))
            codigos_reserva_creados.add(codigo)

    insertar_lote_idempotente(
        conn,
        "reserva",
        ["codigo_reserva", "fecha_reserva_utc", "estado_reserva", "fecha_actualizacion_utc"],
        datos_reservas,
        "codigo_reserva"
    )

    # 3. Tabla 'vuelo'
    with conn.cursor() as cur:
        cur.execute("SELECT id_estado_vuelo FROM estado_vuelo WHERE codigo = 'PROGRAMADO'")
        id_estado_programado = cur.fetchone()[0]

        cur.execute("SELECT id_ruta, duracion_estimada_min FROM ruta")
        rutas = cur.fetchall()

        cur.execute("SELECT id_aeronave FROM aeronave")
        aeronaves = [fila[0] for fila in cur.fetchall()]

    if not rutas or not aeronaves:
        print("[!] No hay rutas o aeronaves suficientes para generar vuelos.")
        return

    datos_vuelos = []
    vuelos_creados = set()

    while len(datos_vuelos) < cantidad_base:
        ruta = random.choice(rutas)
        id_ruta, duracion_min = ruta[0], ruta[1]
        id_aeronave = random.choice(aeronaves)
        numero_vuelo = fake.bothify('??####', letters='ABCDEFGHIJKLMNOPQRSTUVWXYZ')

        salida = fake.date_time_this_year()

        if (numero_vuelo, salida) not in vuelos_creados:
            llegada = salida + timedelta(minutes=duracion_min)
            
            datos_vuelos.append((
                id_ruta,
                id_aeronave,
                numero_vuelo,
                salida,
                llegada,
                id_estado_programado
            ))
            vuelos_creados.add((numero_vuelo, salida))

    insertar_lote_idempotente(
        conn,
        "vuelo",
        ["id_ruta", "id_aeronave", "numero_vuelo", "salida_programada_utc", "llegada_programada_utc", "id_estado_vuelo_actual"],
        datos_vuelos,
        "numero_vuelo, salida_programada_utc"
    )
def generar_tiempos_oooi_db(fecha_programada, causa_retraso, tasa_defectos):
    """Calcula los tiempos OOOI devolviendo objetos datetime nativos para psycopg2."""
    
    # 1. OUT (Salida de la puerta)
    minutos_retraso = random.randint(15, 180) if causa_retraso else random.randint(-5, 10)
    out_time = fecha_programada + timedelta(minutes=minutos_retraso)
    
    # 2. OFF (Despegue)
    taxi_out = random.randint(10, 25)
    off_time = out_time + timedelta(minutes=taxi_out)
    
    # 3. ON (Aterrizaje)
    air_time = random.randint(45, 240)
    on_time = off_time + timedelta(minutes=air_time)
    
    # 4. IN (Llegada a la puerta)
    taxi_in = random.randint(5, 15)
    in_time = on_time + timedelta(minutes=taxi_in)
    
    eventos_oooi = {
        "OUT": out_time,
        "OFF": off_time,
        "ON": on_time,
        "IN": in_time
    }
    
    # --- DEFECTO 1: Vuelos cruzando medianoche mal fechados ---
    # Si la llegada cae en el día siguiente respecto a la salida programada
    if in_time.date() > fecha_programada.date() and random.random() < tasa_defectos:
        # Forzamos un error matemático restándole 24 horas solo a la llegada
        eventos_oooi["IN"] = in_time - timedelta(days=1)

    # --- DEFECTO 2: Eventos OOOI faltantes ---
    if random.random() < tasa_defectos:
        # Elegimos un evento al azar y lo volvemos nulo
        evento_perdido = random.choice(list(eventos_oooi.keys()))
        eventos_oooi[evento_perdido] = None
        
    return eventos_oooi

def insertar_nivel_7_y_8_operacion(conn, args):
    print("--- Procesando Niveles 7 y 8: Uniones y Operación (Caos) ---")

    with conn.cursor() as cur:
        cur.execute("SELECT id_reserva FROM reserva")
        reservas = [r[0] for r in cur.fetchall()]
        
        cur.execute("SELECT id_pasajero FROM pasajero")
        pasajeros = [p[0] for p in cur.fetchall()]
        
        cur.execute("SELECT id_vuelo, salida_programada_utc FROM vuelo")
        vuelos = cur.fetchall()

    if not reservas or not pasajeros or not vuelos:
        print("[!] Faltan datos transaccionales base. Abortando Niveles 7 y 8.")
        return

    # 1. Tabla 'reserva_pasajero'
    datos_res_pas = []
    res_pas_creados = set()
    
    for id_reserva in reservas:
        num_pasajeros = random.randint(1, 3)
        pasajeros_asignados = random.sample(pasajeros, num_pasajeros)
        
        for id_pasajero in pasajeros_asignados:
            if (id_reserva, id_pasajero) not in res_pas_creados:
                datos_res_pas.append((id_reserva, id_pasajero))
                res_pas_creados.add((id_reserva, id_pasajero))

    insertar_lote_idempotente(
        conn, 
        "reserva_pasajero", 
        ["id_reserva", "id_pasajero"], 
        datos_res_pas, 
        "id_reserva, id_pasajero"
    )

    # 2. Tablas 'itinerario' y 'detalle_reserva'
    with conn.cursor() as cur:
        cur.execute("SELECT id_reserva_pasajero FROM reserva_pasajero")
        reserva_pasajeros = [rp[0] for rp in cur.fetchall()]

    datos_itinerarios = []
    datos_detalles = []
    asientos_por_vuelo = {}

    for id_res_pas in reserva_pasajeros:
        # Asignamos un vuelo aleatorio al itinerario del pasajero
        vuelo_asignado = random.choice(vuelos)
        id_vuelo, fecha_salida = vuelo_asignado[0], vuelo_asignado[1]
        
        datos_itinerarios.append((
            id_res_pas,
            fecha_salida,
            'CONFIRMADO'
        ))

    insertar_lote_idempotente(
        conn, 
        "itinerario", 
        ["id_reserva_pasajero", "fecha_salida_utc", "estado"], 
        datos_itinerarios, 
        "id_itinerario" # PostgreSQL permite omitir conflictos si no hay Unique explicito para el batch
    )

    with conn.cursor() as cur:
        cur.execute("SELECT id_itinerario, id_reserva_pasajero FROM itinerario")
        itinerarios = cur.fetchall()

    for itinerario in itinerarios:
        id_itinerario = itinerario[0]
        vuelo_asignado = random.choice(vuelos)
        id_vuelo = vuelo_asignado[0]
        
        if id_vuelo not in asientos_por_vuelo:
            asientos_por_vuelo[id_vuelo] = set()
            
        # Generar un asiento único para ese vuelo
        asiento = f"{random.randint(1, 30)}{random.choice(['A', 'B', 'C', 'D', 'E', 'F'])}"
        while asiento in asientos_por_vuelo[id_vuelo]:
            asiento = f"{random.randint(1, 30)}{random.choice(['A', 'B', 'C', 'D', 'E', 'F'])}"
        asientos_por_vuelo[id_vuelo].add(asiento)
        
        datos_detalles.append((
            id_itinerario,
            id_vuelo,
            1, # numero_secuencia
            'ECONOMICA',
            random.choice(['Y', 'B', 'M', 'H']),
            round(random.uniform(50.0, 500.0), 2),
            'USD',
            asiento,
            'CONFIRMADO'
        ))

    insertar_lote_idempotente(
        conn, 
        "detalle_reserva", 
        ["id_itinerario", "id_vuelo", "numero_secuencia", "clase_servicio", "clase_tarifaria", "monto_tarifa_pagada", "moneda", "numero_asiento", "estado_segmento"], 
        datos_detalles, 
        "id_itinerario, numero_secuencia"
    )

    # 3. Tabla 'evento_operacional' (INYECCIÓN DE DEFECTOS OOOI)
    dic_estados = obtener_diccionario_ids(conn, "SELECT codigo, id_estado_vuelo FROM estado_vuelo", "codigo", "id_estado_vuelo")
    mapa_eventos_estados = {
        'OUT': dic_estados.get('SALIDA_PUERTA'),
        'OFF': dic_estados.get('DESPEGADO'),
        'ON': dic_estados.get('ATERRIZADO'),
        'IN': dic_estados.get('LLEGADA_PUERTA')
    }

    with conn.cursor() as cur:
        cur.execute("SELECT codigo FROM causa")
        causas_validas = [c[0] for c in cur.fetchall()]

    datos_eventos = []
    
    for vuelo in vuelos:
        id_vuelo = vuelo[0]
        fecha_programada = vuelo[1]
        
        # 30% de probabilidad de tener una causa de retraso
        causa = random.choice(causas_validas) if random.random() < 0.3 else None
        causa_original = causa
        
        # Defecto: Causa inválida
        if causa and random.random() < args.tasa_defectos:
            causa_original = random.choice(["N/A", "CAUSA_DESCONOCIDA", "ERROR_99"])
            
        # Generar tiempos OOOI con la lógica que inyecta tiempos perdidos y cruces de medianoche
        tiempos_oooi = generar_tiempos_oooi_db(fecha_programada, causa, args.tasa_defectos)
        
        for codigo_evento, fecha_evento in tiempos_oooi.items():
            if fecha_evento is not None:
                id_estado = mapa_eventos_estados[codigo_evento]
                # Creamos una clave idempotente que simula el mensaje de F4
                id_externo = f"EVT-{id_vuelo}-{codigo_evento}-{fecha_evento.timestamp()}"
                
                datos_eventos.append((
                    id_vuelo,
                    id_estado,
                    fecha_evento,
                    codigo_evento,
                    causa_original,
                    id_externo,
                    'PENDIENTE' # estado_validacion inicial
                ))

    insertar_lote_idempotente(
        conn, 
        "evento_operacional", 
        ["id_vuelo", "id_estado_vuelo", "fecha_hora_evento_utc", "codigo_evento", "codigo_causa_original", "id_externo_evento", "estado_validacion"], 
        datos_eventos, 
        "id_externo_evento"
    )

def main():
    parser = argparse.ArgumentParser(description="Script de Seed VuelaData (PostgreSQL)")
    parser.add_argument("--volumen", choices=["small", "full"], default="small")
    parser.add_argument("--tasa-defectos", type=float, default=0.0)
    args = parser.parse_args()

    configurar_semillas(42)
    conn = obtener_conexion()

    print("[*] Conexión a la base de datos establecida correctamente.")
    try:
        #El orden de ejecución es innegociable
        insertar_nivel_1_catalogos(conn)
        insertar_nivel_2_y_3_geografia_y_flota(conn)
        insertar_nivel_4_geometria(conn)
        insertar_nivel_5_y_6_transaccional(conn, args)
        insertar_nivel_7_y_8_operacion(conn, args)

        # Si llegamos a esta línea sin que nada explote, guardamos todo de golpe
        conn.commit()
        print("\n[*] ÉXITO: Transacción completada. Todos los datos fueron guardados en la base de datos.")

    except Exception as e:
        # Si CUALQUIER nivel falla, deshacemos absolutamente todo lo que se intentó hacer en esta ejecución
        conn.rollback()
        print(f"\n[!] ERROR CRÍTICO: {e}")
        print("[*] Rollback ejecutado: Ningún dato a medias fue enviado a la base de datos.")

    finally:
        # Siempre cerramos la conexión
        conn.close()
        print("[*] Proceso de Seed finalizado.")

if __name__ == "__main__":
    main()