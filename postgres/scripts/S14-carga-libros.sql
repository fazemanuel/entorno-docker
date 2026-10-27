
-- S14: Carga de libros para el esquema biblioteca
-- El archivo CSV debe tener seis columnas y una fila de encabezado.

\set ON_ERROR_STOP on

-- Permite indicar otro CSV al ejecutar el script:
-- -v archivo=/scripts/datos/libros_semilla.csv
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

-- Limpiar únicamente las tablas auxiliares de esta carga.
TRUNCATE stg_linea, stg_libro RESTART IDENTITY;

-- Cargar cada línea completa como texto.
COPY stg_linea (linea)
FROM :'archivo'
WITH (FORMAT text);

-- Retirar el encabezado del CSV.
DELETE FROM stg_linea
WHERE n = 1;

-- Separar los seis campos del archivo.
INSERT INTO stg_libro (
    linea_csv,
    contenido,
    num_campos,
    isbn,
    titulo,
    autor,
    categoria,
    anio_publicacion,
    ejemplares_disponibles
)
SELECT
    n,
    linea,
    array_length(string_to_array(linea, ','), 1),
    trim(split_part(linea, ',', 1)),
    trim(split_part(linea, ',', 2)),
    trim(split_part(linea, ',', 3)),
    trim(split_part(linea, ',', 4)),
    trim(split_part(linea, ',', 5)),
    trim(split_part(linea, ',', 6))
FROM stg_linea;


-- 1. Validar cada fila.
-- CASE guarda únicamente el primer motivo que encuentre.
UPDATE stg_libro
SET motivo = CASE
    WHEN num_campos <> 6
        THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'

    WHEN isbn = ''
        THEN 'ISBN vacío'

    WHEN isbn !~ '^[0-9]{13}$'
        THEN 'ISBN no tiene exactamente 13 dígitos'

    WHEN titulo = ''
        THEN 'título vacío'

    WHEN autor = ''
        THEN 'autor vacío'

    WHEN categoria = ''
        THEN 'categoría vacía'

    WHEN anio_publicacion !~ '^[0-9]{1,4}$'
        THEN 'año no numérico o con formato inválido'

    WHEN anio_publicacion::integer NOT BETWEEN 1450 AND 2100
        THEN 'año fuera del rango 1450–2100'

    WHEN ejemplares_disponibles !~ '^-?[0-9]{1,6}$'
        THEN 'cantidad de ejemplares no numérica o con formato inválido'

    WHEN ejemplares_disponibles::integer < 0
        THEN 'cantidad de ejemplares negativa'

    WHEN EXISTS (
        SELECT 1
        FROM libro l
        WHERE l.isbn = stg_libro.isbn
    )
        THEN 'ISBN ya existe en el catálogo'
END;

-- 2. Detectar ISBN repetidos dentro del mismo CSV.
-- Se conserva la primera aparición que haya pasado las validaciones.
UPDATE stg_libro s
SET motivo = 'ISBN repetido en el archivo (línea ' ||
    (
        SELECT MIN(s2.linea_csv)
        FROM stg_libro s2
        WHERE s2.isbn = s.isbn
          AND s2.motivo IS NULL
    ) || ')'
WHERE s.motivo IS NULL
  AND EXISTS (
      SELECT 1
      FROM stg_libro s2
      WHERE s2.isbn = s.isbn
        AND s2.motivo IS NULL
        AND s2.linea_csv < s.linea_csv
  );


-- 3. Insertar las categorías de los libros válidos.
-- Si la categoría ya existe, no se vuelve a insertar.
INSERT INTO categoria (nombre)
SELECT DISTINCT s.categoria
FROM stg_libro s
WHERE s.motivo IS NULL
ON CONFLICT (nombre) DO NOTHING;


-- 4. Insertar los libros válidos.
-- Cada libro queda relacionado con su categoría mediante id_categoria.
INSERT INTO libro (
    isbn,
    titulo,
    autor,
    anio_publicacion,
    id_categoria
)
SELECT
    s.isbn,
    s.titulo,
    s.autor,
    s.anio_publicacion::SMALLINT,
    c.id_categoria
FROM stg_libro s
JOIN categoria c
    ON c.nombre = s.categoria
WHERE s.motivo IS NULL;


-- 5. Crear los ejemplares físicos de cada libro.
-- Si un libro tiene 3 ejemplares disponibles, se crean 3 registros.
INSERT INTO ejemplar (
    isbn,
    numero_copia
)
SELECT
    s.isbn,
    n.numero_copia
FROM stg_libro s
CROSS JOIN LATERAL
    generate_series(
        1,
        s.ejemplares_disponibles::INTEGER
    ) AS n(numero_copia)
WHERE s.motivo IS NULL;


-- 6. Registrar las filas rechazadas en la bitácora.
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
FROM stg_libro
WHERE motivo IS NOT NULL;


-- 7. Confirmar la transacción.
COMMIT;


-- 8. Mostrar el resumen de la carga.
SELECT
    COUNT(*) AS filas_procesadas,
    COUNT(*) FILTER (
        WHERE motivo IS NULL
    ) AS filas_validas,
    COUNT(*) FILTER (
        WHERE motivo IS NOT NULL
    ) AS filas_rechazadas
FROM stg_libro;


-- Mostrar el detalle de los rechazos.
SELECT
    linea_csv,
    contenido,
    motivo
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;