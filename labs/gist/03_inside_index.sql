-- =====================================================================
-- 03. Заглядываем внутрь индекса: страницы, уровни, ключи
-- Требуется индекс pts_p_gist из задания 01 и расширение pageinspect.
-- =====================================================================
SET search_path = gist_lab, public;

-- 3.1. Размер индекса в страницах (страница = 8 КБ)
SELECT pg_relation_size('pts_p_gist') / current_setting('block_size')::int AS pages,
       pg_size_pretty(pg_relation_size('pts_p_gist')) AS size;

-- 3.2. Корень GiST-индекса всегда лежит в блоке 0
SELECT * FROM gist_page_opaque_info(get_raw_page('pts_p_gist', 0));

-- 3.3. Записи корня: ctid = (номер дочерней страницы, 65535),
--      keys = ограничивающий прямоугольник поддерева
SELECT itemoffset, ctid, itemlen, keys
FROM gist_page_items(get_raw_page('pts_p_gist', 0), 'pts_p_gist');

-- 3.4. Обход всего дерева: сколько уровней, сколько страниц на уровне,
--      сколько записей в среднем на странице и насколько они заполнены
WITH RECURSIVE tree AS (
    SELECT 0::bigint AS blkno, 1 AS level
    UNION ALL
    SELECT (i.ctid::text::point)[0]::bigint, t.level + 1
    FROM tree t
    CROSS JOIN LATERAL gist_page_opaque_info(get_raw_page('pts_p_gist', t.blkno)) o
    CROSS JOIN LATERAL gist_page_items_bytea(get_raw_page('pts_p_gist', t.blkno)) i
    WHERE NOT 'leaf' = ANY (o.flags)
)
SELECT t.level,
       count(*)                                        AS pages,
       round(avg(h.free_space))                        AS avg_free_bytes,
       round(avg((h.lower - 24) / 4))                  AS avg_items_per_page
FROM tree t
CROSS JOIN LATERAL (
    SELECT ph.lower, ph.upper - ph.lower AS free_space
    FROM page_header(get_raw_page('pts_p_gist', t.blkno)) ph
) h
GROUP BY t.level
ORDER BY t.level;

-- 3.5. Перекрытие прямоугольников второго уровня (дочерние узлы корня).
--      Чем больше суммарная площадь пересечений, тем чаще поиск
--      вынужден спускаться сразу в несколько ветвей.
WITH root_keys AS (
    SELECT itemoffset,
           regexp_replace(keys, '^\(p\)=\("(.*)"\)$', '\1')::box AS b
    FROM gist_page_items(get_raw_page('pts_p_gist', 0), 'pts_p_gist')
)
SELECT count(*)                                         AS children,
       round(sum(area(b))::numeric)                     AS total_area,
       round(area(box '((0,0),(1000,1000))')::numeric)  AS space_area,
       (SELECT count(*)
          FROM root_keys a JOIN root_keys c
            ON a.itemoffset < c.itemoffset AND a.b && c.b) AS overlapping_pairs,
       (SELECT round(sum(area(a.b # c.b))::numeric)
          FROM root_keys a JOIN root_keys c
            ON a.itemoffset < c.itemoffset AND a.b && c.b) AS overlap_area
FROM root_keys;

-- 3.6. Лист: здесь ctid указывает уже на строку таблицы,
--      а ключ — вырожденный прямоугольник из одной точки.
--      Спускаемся от корня по первой записи каждого узла до листа.
WITH RECURSIVE path AS (
    SELECT 0::bigint AS blkno
    UNION ALL
    SELECT (SELECT (i.ctid::text::point)[0]::bigint
              FROM gist_page_items_bytea(get_raw_page('pts_p_gist', p.blkno)) i
             LIMIT 1)
    FROM path p
    WHERE NOT 'leaf' = ANY ((gist_page_opaque_info(get_raw_page('pts_p_gist', p.blkno))).flags)
),
leaf AS (
    SELECT blkno FROM path
    WHERE 'leaf' = ANY ((gist_page_opaque_info(get_raw_page('pts_p_gist', blkno))).flags)
)
SELECT leaf.blkno AS leaf_block, i.itemoffset, i.ctid, i.keys, t.id, t.p
FROM leaf
CROSS JOIN LATERAL gist_page_items(get_raw_page('pts_p_gist', leaf.blkno), 'pts_p_gist') i
JOIN pts t ON t.ctid = i.ctid
ORDER BY i.itemoffset
LIMIT 10;
