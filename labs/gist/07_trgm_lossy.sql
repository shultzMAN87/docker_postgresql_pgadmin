-- =====================================================================
-- 07. Неточный (lossy) индекс: триграммы, GiST против GIN, siglen
-- Время выполнения: 1–2 минуты.
-- =====================================================================
SET search_path = gist_lab, public;

-- 7.1. 300 000 «фамилий», собранных из слогов
DROP TABLE IF EXISTS names;
SELECT setseed(0.3);
CREATE TABLE names AS
WITH syl AS (
    SELECT array['ко','ва','лев','ма','ри','ин','со','ро','ки','не','ба','ту',
                 'ше','ло','да','ник','пе','тр','ов','ан','ер','ск','ий','ус'] AS s
)
SELECT g AS id,
       initcap(
         s[1 + (random() * 23)::int] || s[1 + (random() * 23)::int] ||
         s[1 + (random() * 23)::int] ||
         CASE WHEN random() < 0.5 THEN s[1 + (random() * 23)::int] ELSE '' END ||
         (array['ов','ев','ин','ский','ко','ук'])[1 + (random() * 5)::int]
       ) AS name
FROM generate_series(1, 300000) AS g, syl;
ANALYZE names;

SELECT name FROM names LIMIT 10;

-- Как pg_trgm видит строку
SELECT show_trgm('Ковалев');

-- 7.2. Три индекса: GiST (siglen по умолчанию = 12 байт), GiST с siglen = 64, GIN
DO $$
DECLARE t timestamptz;
BEGIN
    t := clock_timestamp();
    CREATE INDEX names_gist12 ON names USING gist (name gist_trgm_ops);
    RAISE NOTICE 'GiST siglen=12: %', clock_timestamp() - t;

    t := clock_timestamp();
    CREATE INDEX names_gist64 ON names USING gist (name gist_trgm_ops(siglen = 64));
    RAISE NOTICE 'GiST siglen=64: %', clock_timestamp() - t;

    t := clock_timestamp();
    CREATE INDEX names_gin ON names USING gin (name gin_trgm_ops);
    RAISE NOTICE 'GIN:            %', clock_timestamp() - t;
END $$;

SELECT indexrelid::regclass AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index WHERE indrelid = 'names'::regclass ORDER BY 1;

-- 7.3. Поиск подстроки LIKE '%...%' каждым индексом по очереди.
--      Остальные индексы временно удаляем внутри транзакции и откатываем.
BEGIN;
DROP INDEX names_gist64, names_gin;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM names WHERE name LIKE '%левма%';
ROLLBACK;

BEGIN;
DROP INDEX names_gist12, names_gin;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM names WHERE name LIKE '%левма%';
ROLLBACK;

BEGIN;
DROP INDEX names_gist12, names_gist64;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM names WHERE name LIKE '%левма%';
ROLLBACK;

-- 7.4. Нечёткий поиск: 5 самых похожих на строку с опечаткой (KNN по <->).
--      Сравните план с GiST и с одним только GIN.
BEGIN;
DROP INDEX names_gist12, names_gin;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT name, name <-> 'Ковалеввский' AS dist
FROM names ORDER BY name <-> 'Ковалеввский' LIMIT 5;

SELECT name, round((name <-> 'Ковалеввский')::numeric, 3) AS dist
FROM names ORDER BY name <-> 'Ковалеввский' LIMIT 5;
ROLLBACK;

BEGIN;
DROP INDEX names_gist12, names_gist64;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT name, name <-> 'Ковалеввский' AS dist
FROM names ORDER BY name <-> 'Ковалеввский' LIMIT 5;
ROLLBACK;
