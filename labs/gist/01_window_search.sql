-- =====================================================================
-- 01. Поиск в прямоугольной области: без индекса, B-tree, GiST
-- =====================================================================
SET search_path = gist_lab, public;

-- Скрипт можно запускать повторно
DROP INDEX IF EXISTS pts_xy_btree, pts_p_gist;

-- Запрос: сколько точек попадает в квадрат 10 x 10
-- 1.1. Без индексов
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts WHERE p <@ box '((100,100),(110,110))';

-- 1.2. Составной B-tree по координатам (так сделали бы без GiST)
CREATE INDEX pts_xy_btree ON pts ((p[0]), (p[1]));
ANALYZE pts;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts
WHERE p[0] BETWEEN 100 AND 110
  AND p[1] BETWEEN 100 AND 110;

-- 1.3. GiST-индекс по точке
CREATE INDEX pts_p_gist ON pts USING gist (p);
ANALYZE pts;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts WHERE p <@ box '((100,100),(110,110))';

-- 1.4. Тот же запрос, но нужны все столбцы строки
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT * FROM pts WHERE p <@ box '((100,100),(110,110))';

-- 1.5. Размеры индексов
SELECT indexrelid::regclass AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index
WHERE indrelid = 'pts'::regclass
ORDER BY 1;

-- 1.6. Вытянутые области одинаковой площади (10 x 1000)
-- B-tree: полоса по первому столбцу (x) и по второму (y)
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts WHERE p[0] BETWEEN 100 AND 110 AND p[1] BETWEEN 0 AND 1000;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts WHERE p[0] BETWEEN 0 AND 1000 AND p[1] BETWEEN 100 AND 110;

-- GiST: те же две полосы
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts WHERE p <@ box '((100,0),(110,1000))';

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM pts WHERE p <@ box '((0,100),(1000,110))';

-- Удаляем B-tree, дальше он не нужен
DROP INDEX pts_xy_btree;
