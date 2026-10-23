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

-- Пункт 4. HAVING: фильтрация групп по результату агрегации.
-- Назначение: продавцы с выручкой больше 15 млн руб. Выручка — сумма
-- (количество * цена на момент покупки) по позициям неотменённых заказов.
-- WHERE отбрасывает строки отменённых заказов до группировки,
-- HAVING отбирает продавцов по сумме уже после группировки.
SELECT
    s.id,
    s.store_name                     AS seller,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products    AS p  ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
JOIN orders      AS o  ON o.id = oi.order_id
WHERE o.status <> 'cancelled'
GROUP BY s.id, s.store_name
HAVING SUM(oi.quantity * oi.unit_price) > 15000000
ORDER BY revenue DESC;

-- Пункт 5.1. Скалярный подзапрос (возвращает ровно одно значение).
-- Назначение: товары дороже средней цены по всему каталогу; та же средняя
-- цена выводится рядом в отдельном столбце для сравнения.
SELECT
    id,
    title,
    price,
    (SELECT ROUND(AVG(price), 2) FROM products) AS avg_price
FROM products
WHERE price > (SELECT AVG(price) FROM products)
ORDER BY id ASC
LIMIT 10;

-- Пункт 5.2. Подзапрос в предикате IN (возвращает множество значений).
-- Назначение: товары из подкатегорий «Электроники» (категории, у которых
-- parent_id = 1).
SELECT
    id,
    title,
    price,
    category_id
FROM products
WHERE category_id IN (SELECT id FROM categories WHERE parent_id = 1)
ORDER BY id ASC
LIMIT 10;

-- Пункт 5.3. Коррелированный подзапрос в предикате EXISTS.
-- Назначение: покупатели, у которых есть хотя бы один отменённый заказ.
-- Подзапрос ссылается на u.id внешнего запроса, поэтому логически
-- вычисляется для каждого пользователя.
SELECT
    u.id,
    u.full_name,
    u.email
FROM users AS u
WHERE EXISTS (SELECT 1
              FROM orders AS o
              WHERE o.user_id = u.id
                AND o.status = 'cancelled')
ORDER BY u.id ASC
LIMIT 10;
