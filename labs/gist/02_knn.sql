-- =====================================================================
-- 02. KNN: поиск k ближайших соседей (оператор <->)
-- Требуется индекс pts_p_gist из задания 01.
-- =====================================================================
SET search_path = gist_lab, public;

-- 2.1. 10 ближайших точек к центру с индексом
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, p, p <-> point '(500,500)' AS dist
FROM pts
ORDER BY p <-> point '(500,500)'
LIMIT 10;

-- 2.2. То же самое, но индексный доступ запрещён
SET enable_indexscan = off;
SET enable_indexonlyscan = off;
SET enable_bitmapscan = off;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, p, p <-> point '(500,500)' AS dist
FROM pts
ORDER BY p <-> point '(500,500)'
LIMIT 10;

RESET enable_indexscan;
RESET enable_indexonlyscan;
RESET enable_bitmapscan;

-- 2.3. Как растёт стоимость с ростом k: 10, 1 000, 100 000
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id FROM pts ORDER BY p <-> point '(500,500)' LIMIT 1000;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id FROM pts ORDER BY p <-> point '(500,500)' LIMIT 100000;

-- 2.4. KNN с дополнительным фильтром
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, p FROM pts
WHERE id % 1000 = 0
ORDER BY p <-> point '(500,500)'
LIMIT 10;

-- 2.5. KNN от точки в углу и за пределами облака точек
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id FROM pts ORDER BY p <-> point '(0,0)' LIMIT 10;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id FROM pts ORDER BY p <-> point '(5000,5000)' LIMIT 10;
