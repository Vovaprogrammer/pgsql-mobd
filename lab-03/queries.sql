-- =============================================================================
-- Лабораторная работа №3. Многотабличные запросы и аналитические представления
-- Запросы к базе marketplace (после schema.sql и seed.sql).
-- Номера соответствуют пунктам технического задания.
-- =============================================================================

-- Пункт 1. Внутреннее соединение трёх таблиц: товар — категория — продавец.
-- Назначение: карточки активных товаров с названием категории и магазина
-- вместо числовых идентификаторов.
SELECT
    p.id,
    p.title,
    c.name       AS category,
    s.store_name AS seller,
    p.price
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers    AS s ON s.id = p.seller_id
WHERE p.is_active = TRUE
ORDER BY p.id ASC
LIMIT 10;

-- Пункт 2. LEFT JOIN: строки без соответствия в связанной таблице.
-- Назначение: товары вместе с их отзывами. LEFT JOIN сохраняет все товары;
-- у товара без отзывов столбцы reviews заполняются NULL.
SELECT
    p.id,
    p.title,
    p.price,
    r.id AS review_id
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
ORDER BY p.id ASC
LIMIT 10;

-- Пункт 3. Группировка и агрегация.
-- Назначение: по каждой категории — количество товаров и средняя цена.
SELECT
    c.id,
    c.name                 AS category,
    COUNT(*)               AS products_count,
    ROUND(AVG(p.price), 2) AS avg_price
FROM categories AS c
JOIN products AS p ON p.category_id = c.id
GROUP BY c.id, c.name
ORDER BY avg_price DESC;
