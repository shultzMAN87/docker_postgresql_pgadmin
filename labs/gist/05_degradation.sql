-- =====================================================================
-- 05. Деградация индекса при изменениях данных и REINDEX
-- Требуются функции avg_buffers и root_overlap из задания 04.
-- Время выполнения: 1–3 минуты.
-- =====================================================================
SET search_path = gist_lab, public;

DROP TABLE IF EXISTS pts_d;
CREATE TABLE pts_d AS SELECT * FROM pts;
CREATE INDEX pts_d_gist ON pts_d USING gist (p);
VACUUM ANALYZE pts_d;

DROP TABLE IF EXISTS degradation_log;
CREATE TABLE degradation_log (
    step        text,
    index_size  text,
    avg_buf     numeric,
    children    bigint,
    overlap     numeric
);

INSERT INTO degradation_log
SELECT '1. после создания', pg_size_pretty(pg_relation_size('pts_d_gist')),
       avg_buffers('pts_d', 200, 10), o.children, o.overlap_area
FROM root_overlap('pts_d_gist') o;

-- 5.1. Три раунда «перемещения» всех точек в случайные места
UPDATE pts_d SET p = point(random() * 1000, random() * 1000);
VACUUM pts_d;
UPDATE pts_d SET p = point(random() * 1000, random() * 1000);
VACUUM pts_d;
UPDATE pts_d SET p = point(random() * 1000, random() * 1000);
VACUUM ANALYZE pts_d;

INSERT INTO degradation_log
SELECT '2. после 3 UPDATE всех строк', pg_size_pretty(pg_relation_size('pts_d_gist')),
       avg_buffers('pts_d', 200, 10), o.children, o.overlap_area
FROM root_overlap('pts_d_gist') o;

-- 5.2. Удаляем всю левую половину квадрата
DELETE FROM pts_d WHERE p[0] < 500;
VACUUM ANALYZE pts_d;

INSERT INTO degradation_log
SELECT '3. после DELETE половины', pg_size_pretty(pg_relation_size('pts_d_gist')),
       avg_buffers('pts_d', 200, 10), o.children, o.overlap_area
FROM root_overlap('pts_d_gist') o;

-- Поиск в области, где точек больше нет
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts_d WHERE p <@ box '((100,100),(400,400))';

-- 5.3. Перестраиваем индекс
REINDEX INDEX pts_d_gist;

INSERT INTO degradation_log
SELECT '4. после REINDEX', pg_size_pretty(pg_relation_size('pts_d_gist')),
       avg_buffers('pts_d', 200, 10), o.children, o.overlap_area
FROM root_overlap('pts_d_gist') o;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts_d WHERE p <@ box '((100,100),(400,400))';

SELECT * FROM degradation_log ORDER BY step;
