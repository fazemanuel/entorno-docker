# entorno-docker

Entorno Docker para el proyecto de base de datos (biblioteca): PostgreSQL 16 con esquema, scripts de carga desde CSV y pgAdmin/Mongo disponibles.

## Requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (incluye `docker compose`)
- Git

## 1. Clonar el repositorio

```powershell
git clone https://github.com/fazemanuel/entorno-docker.git
cd entorno-docker
```

## 2. Levantar PostgreSQL

```powershell
docker compose up -d postgres
```

La primera vez, el contenedor crea la base `tienda` (usuario `curso` / clave `curso`) y ejecuta automáticamente el esquema:

- `postgres/init/01_esquema.sql` — esquema `biblioteca` (tablas: rol, usuario, categoria, libro, ejemplar, prestamo, rechazo_carga y tablas de staging). Se ejecuta **solo una vez**, cuando la base se crea vacía.
- `postgres/scripts/` queda montado en `/scripts` dentro del contenedor (scripts que se corren a mano).

Espera ~15 segundos y verifica que todo quedó creado:

```powershell
Start-Sleep -Seconds 15
docker compose logs postgres | Select-String "01_esquema|ERROR|ready"
docker compose exec postgres psql -U curso -d tienda -c "\dt biblioteca.*"
```

Deberías ver las 10 tablas del esquema `biblioteca` (categoria, ejemplar, libro, prestamo, rechazo_carga, rol, stg_lector, stg_libro, stg_linea, usuario).

## 3. Cargar datos desde CSV (a mano, cuando quieras)

Los CSV están en `postgres/scripts/datos/` → dentro del contenedor: `/scripts/datos/…`

```powershell
# Carga de libros (usa por defecto /scripts/datos/libros_semilla.csv)
docker compose exec postgres psql -U curso -d tienda -f /scripts/S14-carga-libros.sql

# Carga de lectores
docker compose exec postgres psql -U curso -d tienda -f /scripts/S14-carga-lectores.sql

# Para probar con otro CSV (p. ej. el de errores):
docker compose exec postgres psql -U curso -d tienda `
  -f /scripts/S14-carga-libros.sql -v archivo=/scripts/datos/libros_semilla_con_errores.csv
```

Estos scripts **no borran la base**: se pueden correr cuantas veces haga falta.

Conexión interactiva:

```powershell
docker compose exec postgres psql -U curso -d tienda
# dentro: \i /scripts/S14-carga-libros.sql
```

## 4. Levantar el resto de servicios (opcional)

```powershell
docker compose up -d        # todo: postgres + mongo
```

- PostgreSQL: `localhost:5432` (curso / curso, base `tienda`)
- MongoDB: `localhost:27017` (curso / curso)

## 5. Apagar y reiniciar de cero

```powershell
docker compose down          # detiene los contenedores (los datos persisten en el volumen)
```

Para **empezar de cero** (borra los datos y re-ejecuta el esquema):

```powershell
docker compose down -v
docker compose up -d postgres
```

## Estructura

```
entorno-docker/
├── docker-compose.yml          # servicios postgres y mongo
├── postgres/
│   ├── init/                   # esquema: se ejecuta solo al crear la base (una vez)
│   │   └── 01_esquema.sql
│   ├── scripts/                # scripts que se corren a mano (cargas, consultas)
│   │   ├── S14-carga-libros.sql
│   │   ├── S14-carga-lectores.sql
│   │   └── datos/              # CSV semilla y CSV con errores de prueba
│   └── data/                   # datos del contenedor (ignorado por git)
├── pgadmin/
├── node/
└── S14_Laboratorio.pdf         # documentación del taller S14
```
