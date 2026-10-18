-- =====================================================================
-- 00. Подготовка стенда для заданий по GiST
-- Создаёт схему gist_lab и тестовые данные (~1 млн точек).
-- Скрипт можно запускать повторно: схема пересоздаётся с нуля.
-- Время выполнения: 10–40 секунд.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pageinspect;  -- чтение страниц индекса
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- скалярные типы в GiST
CREATE EXTENSION IF NOT EXISTS pg_trgm;      -- триграммы

DROP SCHEMA IF EXISTS gist_lab CASCADE;
CREATE SCHEMA gist_lab;
SET search_path = gist_lab, public;

-- Фиксируем генератор случайных чисел, чтобы данные были одинаковыми
SELECT setseed(0.42);

-- 1 000 000 точек, равномерно разбросанных по квадрату 1000 x 1000
CREATE TABLE pts AS
SELECT g AS id,
       point(random() * 1000, random() * 1000) AS p
FROM generate_series(1, 1000000) AS g;

ALTER TABLE pts ADD PRIMARY KEY (id);

-- VACUUM заполняет карту видимости: без неё не будет Index Only Scan
VACUUM ANALYZE pts;

SELECT count(*) AS points, pg_size_pretty(pg_total_relation_size('pts')) AS table_size
FROM pts;
