-- =====================================================================
-- 04. Способы построения индекса и качество дерева
--   A) CREATE INDEX по заполненной таблице (по умолчанию — sorted build,
--      если у класса операторов есть sortsupport, как у point)
--   B) CREATE INDEX ... WITH (buffering = on) — буферизованная сборка
--   C) индекс создан на пустой таблице, строки вставляются по одной
--      (каждая вставка идёт через penalty/picksplit)
-- Время выполнения: 1–3 минуты.
-- =====================================================================
SET search_path = gist_lab, public;

DROP TABLE IF EXISTS pts_a, pts_b, pts_c;
CREATE TABLE pts_a AS SELECT * FROM pts;
CREATE TABLE pts_b AS SELECT * FROM pts;
CREATE TABLE pts_c (LIKE pts);

-- 4.1. Время построения
DO $$
DECLARE t timestamptz;
BEGIN
    t := clock_timestamp();
    CREATE INDEX pts_a_gist ON pts_a USING gist (p);
    RAISE NOTICE 'A) sorted build (по умолчанию): %', clock_timestamp() - t;

    t := clock_timestamp();
    CREATE INDEX pts_b_gist ON pts_b USING gist (p) WITH (buffering = on);
    RAISE NOTICE 'B) buffering build:            %', clock_timestamp() - t;

    t := clock_timestamp();
    CREATE INDEX pts_c_gist ON pts_c USING gist (p);
    INSERT INTO pts_c SELECT * FROM pts;
    RAISE NOTICE 'C) вставка по одной строке:    %', clock_timestamp() - t;
END $$;

VACUUM ANALYZE pts_a;
VACUUM ANALYZE pts_b;
VACUUM ANALYZE pts_c;

-- Вспомогательная функция: среднее число прочитанных страниц
-- на запрос по N случайным квадратам заданного размера
CREATE OR REPLACE FUNCTION avg_buffers(tbl regclass, n int DEFAULT 200, side float8 DEFAULT 10)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE
    plan json;
    total bigint := 0;
    x float8; y float8;
BEGIN
    PERFORM setseed(0.1);
    FOR i IN 1..n LOOP
        x := random() * (1000 - side);
        y := random() * (1000 - side);
        EXECUTE format(
            'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT count(*) FROM %s WHERE p <@ box(point(%s,%s), point(%s,%s))',
            tbl, x, y, x + side, y + side)
        INTO plan;
        total := total
               + (plan -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint
               + (plan -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint;
    END LOOP;
    RETURN round(total::numeric / n, 1);
END $$;

-- Вспомогательная функция: перекрытие прямоугольников у дочерних узлов корня
CREATE OR REPLACE FUNCTION root_overlap(idx regclass)
RETURNS TABLE (children bigint, total_area numeric, overlap_area numeric)
LANGUAGE sql AS $$
    WITH k AS (
        SELECT itemoffset,
               regexp_replace(keys, '^\(p\)=\("(.*)"\)$', '\1')::box AS b
        FROM gist_page_items(get_raw_page(idx::text, 0), idx)
    )
    SELECT (SELECT count(*) FROM k),
           (SELECT round(sum(area(b))::numeric) FROM k),
           (SELECT coalesce(round(sum(area(a.b # c.b))::numeric), 0)
              FROM k a JOIN k c ON a.itemoffset < c.itemoffset AND a.b && c.b)
$$;

-- 4.2. Сравнение: размер, перекрытие на втором уровне,
--      стоимость поиска маленьких (10x10) и больших (100x100) квадратов
SELECT v.variant,
       pg_size_pretty(pg_relation_size(v.idx))           AS size,
       pg_relation_size(v.idx) / 8192                     AS pages,
       o.children                                         AS root_children,
       o.total_area                                       AS root_children_area,
       o.overlap_area                                     AS root_overlap_area,
       avg_buffers(v.tbl, 200, 10)                        AS avg_buf_10x10,
       avg_buffers(v.tbl, 50, 100)                        AS avg_buf_100x100
FROM (VALUES ('A sorted',    'pts_a'::regclass, 'pts_a_gist'::regclass),
             ('B buffering', 'pts_b'::regclass, 'pts_b_gist'::regclass),
             ('C inserts',   'pts_c'::regclass, 'pts_c_gist'::regclass)) AS v(variant, tbl, idx)
CROSS JOIN LATERAL root_overlap(v.idx) o;
