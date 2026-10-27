
-- S14: Carga de lectores para el esquema biblioteca
-- El CSV debe tener cinco columnas y una fila de encabezado:
-- documento,nombres,apellidos,correo,telefono

\set ON_ERROR_STOP on

\if :{?archivo}
\else
    \set archivo /scripts/datos/lectores_semilla.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

-- 1. Limpiar las tablas de trabajo de esta carga.
TRUNCATE stg_linea, stg_lector RESTART IDENTITY;

-- 2. Leer el CSV como líneas completas de texto.
COPY stg_linea (linea)
FROM :'archivo'
WITH (FORMAT text);

-- Conservar el número de línea original del archivo.
-- La primera línea es el encabezado.
DELETE FROM stg_linea
WHERE n = 1;

-- 3. Separar las cinco columnas del CSV.
INSERT INTO stg_lector (
    linea_csv,
    contenido,
    num_campos,
    documento,
    nombres,
    apellidos,
    correo,
    telefono
)
SELECT
    n,
    linea,
    array_length(string_to_array(linea, ','), 1),
    trim(split_part(linea, ',', 1)),
    trim(split_part(linea, ',', 2)),
    trim(split_part(linea, ',', 3)),
    lower(trim(split_part(linea, ',', 4))),
    trim(split_part(linea, ',', 5))
FROM stg_linea;

-- 4. Validar cada fila.
-- Se guarda solamente el primer error encontrado.
UPDATE stg_lector
SET motivo = CASE
    WHEN num_campos <> 5
        THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'

    WHEN documento = ''
        THEN 'documento vacío'

    WHEN documento !~ '^[0-9]{6,15}$'
        THEN 'documento debe tener entre 6 y 15 dígitos'

    WHEN nombres = ''
        THEN 'nombres vacíos'

    WHEN apellidos = ''
        THEN 'apellidos vacíos'

    WHEN correo = ''
        THEN 'correo vacío'

    WHEN correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'
        THEN 'formato de correo inválido'

    WHEN telefono <> ''
         AND telefono !~ '^[0-9]{7,15}$'
        THEN 'teléfono debe tener entre 7 y 15 dígitos'

    WHEN EXISTS (
        SELECT 1
        FROM usuario u
        WHERE u.documento = stg_lector.documento
    )
        THEN 'documento ya existe en el sistema'

    WHEN EXISTS (
        SELECT 1
        FROM usuario u
        WHERE lower(u.correo) = stg_lector.correo
    )
        THEN 'correo ya existe en el sistema'
END;

-- 5. Detectar documentos o correos repetidos dentro del CSV.
-- Se conserva la primera fila válida de cada documento y correo.
UPDATE stg_lector s
SET motivo = CASE
    WHEN EXISTS (
        SELECT 1
        FROM stg_lector s2
        WHERE s2.documento = s.documento
          AND s2.linea_csv < s.linea_csv
          AND s2.motivo IS NULL
    )
        THEN 'documento repetido en el archivo'

    WHEN EXISTS (
        SELECT 1
        FROM stg_lector s2
        WHERE s2.correo = s.correo
          AND s2.linea_csv < s.linea_csv
          AND s2.motivo IS NULL
    )
        THEN 'correo repetido en el archivo'
END
WHERE s.motivo IS NULL
  AND (
      EXISTS (
          SELECT 1
          FROM stg_lector s2
          WHERE s2.documento = s.documento
            AND s2.linea_csv < s.linea_csv
            AND s2.motivo IS NULL
      )
      OR EXISTS (
          SELECT 1
          FROM stg_lector s2
          WHERE s2.correo = s.correo
            AND s2.linea_csv < s.linea_csv
            AND s2.motivo IS NULL
      )
  );

-- 6 Insertar los lectores válidos.
-- El documento funciona como contraseña inicial.
-- En la base de datos se guarda su hash, no el documento como contraseña.
INSERT INTO usuario (
    documento,
    nombres,
    apellidos,
    correo,
    telefono,
    clave_hash,
    tipo_rol
)
SELECT
    documento,
    nombres,
    apellidos,
    correo,
    NULLIF(telefono, ''),
    crypt(documento, gen_salt('bf')),
    'Lector'
FROM stg_lector
WHERE motivo IS NULL;

-- 7. Guardar los rechazos en la bitácora común.
INSERT INTO rechazo_carga (
    archivo,
    linea,
    contenido,
    motivo
)
SELECT
    :'archivo',
    linea_csv,
    contenido,
    motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

COMMIT;

-- 8. Resumen de la carga.
SELECT
    COUNT(*) AS filas_procesadas,
    COUNT(*) FILTER (WHERE motivo IS NULL) AS filas_validas,
    COUNT(*) FILTER (WHERE motivo IS NOT NULL) AS filas_rechazadas
FROM stg_lector;

-- Detalle de las filas rechazadas.
SELECT linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
