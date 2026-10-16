# VuelaData - Base de Datos Transaccional y Seed

Este repositorio contiene la inicialización de la base de datos PostgreSQL (HU-03) y su respectiva documentación técnica interactiva.

## 1. Ejecutar la inicialización de la Base de Datos
1. Configurar las credenciales en un archivo `.env` basado en el `.env.example`.
2. Instalar las dependencias de Python:
   `pip install -r requirements.txt`
3. Ejecutar el script de Seed:
   `python seed.py --volumen small --tasa-defectos 0.1`

## 2. Ver la Documentación Técnica
La documentación de las tablas, el esquema y las reglas de negocio está construida con Docusaurus. Para visualizarla localmente:

1. Navegar a la carpeta de la web:
   `cd website`
2. Instalar los paquetes de Node (solo la primera vez):
   `npm install`
3. Levantar el servidor:
   `npm run start`

La documentación se abrirá automáticamente en `http://localhost:3000`.