-- =====================================================================
-- 06. Диапазоны и ограничение исключения (EXCLUDE USING gist)
-- Задача: бронирование переговорных без пересечений по времени.
-- =====================================================================
SET search_path = gist_lab, public;

DROP TABLE IF EXISTS booking;
CREATE TABLE booking (
    id      bigserial PRIMARY KEY,
    room    int       NOT NULL,
    during  tstzrange NOT NULL,
    author  text,
    -- В одной комнате интервалы не должны пересекаться.
    -- room WITH = работает в GiST только благодаря btree_gist.
    CONSTRAINT booking_no_overlap
        EXCLUDE USING gist (room WITH =, during WITH &&)
);

-- 6.1. Заполняем: 50 комнат, по 2 000 часовых встреч в каждой без пересечений.
--      Нечётные комнаты заняты в нечётные часы от начала отсчёта, чётные — в чётные.
SELECT setseed(0.7);
INSERT INTO booking (room, during, author)
SELECT r,
       tstzrange(ts, ts + interval '1 hour'),
       'user' || (random() * 100)::int
FROM generate_series(1, 50) AS r,
     generate_series(1, 2000) AS n,
     LATERAL (SELECT timestamptz '2026-01-01 09:00' + (n * 2 + r % 2) * interval '1 hour') AS t(ts);

ANALYZE booking;

-- 6.2. Какой индекс создала СУБД под ограничение
SELECT indexrelid::regclass AS index_name,
       pg_get_indexdef(indexrelid) AS definition
FROM pg_index WHERE indrelid = 'booking'::regclass;

-- 6.3. Попытки вставить пересекающиеся брони
DO $$
DECLARE r booking;
BEGIN
    SELECT * INTO r FROM booking WHERE room = 7 ORDER BY id LIMIT 1 OFFSET 10;
    RAISE NOTICE 'Существующая бронь комнаты 7: %', r.during;

    -- а) пересечение на полчаса — должно упасть
    BEGIN
        INSERT INTO booking (room, during, author)
        VALUES (7, tstzrange(lower(r.during) + interval '30 min',
                             upper(r.during) + interval '30 min'), 'test');
        RAISE NOTICE 'а) вставлено (неожиданно!)';
    EXCEPTION WHEN exclusion_violation THEN
        RAISE NOTICE 'а) отказ: %', SQLERRM;
    END;

    -- б) встык: начало новой = конец существующей
    BEGIN
        INSERT INTO booking (room, during, author)
        VALUES (7, tstzrange(upper(r.during), upper(r.during) + interval '30 min'), 'test');
        RAISE NOTICE 'б) вставлено';
    EXCEPTION WHEN exclusion_violation THEN
        RAISE NOTICE 'б) отказ: %', SQLERRM;
    END;

    -- в) то же время, но другая комната
    BEGIN
        INSERT INTO booking (room, during, author)
        VALUES (8, r.during, 'test');
        RAISE NOTICE 'в) отказ не возник — другая комната';
    EXCEPTION WHEN exclusion_violation THEN
        RAISE NOTICE 'в) отказ: %', SQLERRM;
    END;
END $$;

-- 6.4. Поиск: кто занимает комнату 7 в заданный момент
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT * FROM booking
WHERE room = 7 AND during @> timestamptz '2026-02-10 12:30';

-- 6.5. Поиск: все брони, пересекающиеся с интервалом, по всем комнатам
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT room, during FROM booking
WHERE during && tstzrange('2026-02-10 10:00', '2026-02-10 14:00');

-- 6.6. Свободна ли комната 7 на интервал (типичная проверка перед вставкой)
SELECT NOT EXISTS (
    SELECT 1 FROM booking
    WHERE room = 7 AND during && tstzrange('2026-02-10 10:00', '2026-02-10 11:00')
) AS is_free;
