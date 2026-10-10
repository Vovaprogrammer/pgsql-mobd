-- =============================================================================
-- Лабораторная работа №2. Базовые SQL-запросы и фильтрация данных
-- Запросы к базе marketplace (после schema.sql и seed.sql).
-- Номера соответствуют пунктам технического задания.
-- =============================================================================

-- Пункт 2. Столбцы товаров без дубликатов (DISTINCT) с псевдонимами.
-- Назначение: какие сочетания «категория — признак активности» есть в каталоге.
SELECT DISTINCT
    category_id AS category,
    is_active AS active
FROM products
ORDER BY category ASC, active ASC;

-- Пункт 3 (+ IN из пункта 4). Условия с AND, OR и скобками.
-- Назначение: активные товары дешевле 2000 или из категорий 7 (смартфоны)
-- и 8 (ноутбуки).
SELECT
    id,
    title,
    price,
    category_id,
    is_active
FROM products
WHERE is_active = TRUE
  AND (price < 2000 OR category_id IN (7, 8))
ORDER BY id ASC
LIMIT 10;

-- Пункт 4. BETWEEN: товары с ценой от 3000 до 5000.
SELECT id, title, price
FROM products
WHERE price BETWEEN 3000 AND 5000
ORDER BY price ASC
LIMIT 10;

-- Пункт 4. ILIKE: поиск смартфонов по названию (регистр не важен).
SELECT id, title, price
FROM products
WHERE title ILIKE '%смартфон%'
ORDER BY id ASC
LIMIT 10;

-- Пункт 4. IS NULL: товары без описания; COALESCE подставляет текст вместо NULL.
SELECT
    id,
    title,
    COALESCE(description, 'нет описания') AS descr
FROM products
WHERE description IS NULL
ORDER BY id ASC
LIMIT 10;

-- Пункт 5. Сортировка по двум столбцам в разных направлениях:
-- самые дорогие активные товары, при равной цене — по названию.
SELECT id, title, price
FROM products
WHERE is_active = TRUE
ORDER BY price DESC, title ASC
LIMIT 10;

-- Пункт 6. Постраничный вывод: страница 2 по 20 товаров
-- (OFFSET = (номер страницы - 1) * 20; для страницы 1 — OFFSET 0).
SELECT id, title, price
FROM products
ORDER BY id ASC
LIMIT 20 OFFSET 20;
