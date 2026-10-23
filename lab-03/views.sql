-- =============================================================================
-- Лабораторная работа №3. Пункт 7. Представления для типовых отчётов
-- Запускать после schema.sql и seed.sql, подключившись к базе marketplace.
-- Скрипт можно выполнять повторно: представления удаляются и создаются заново.
-- =============================================================================

DROP VIEW IF EXISTS seller_revenue;
DROP VIEW IF EXISTS product_rating;

-- -----------------------------------------------------------------------------
-- seller_revenue — выручка каждого продавца (без отменённых заказов).
-- Выручка — сумма (количество * цена на момент покупки) по позициям заказов
-- с товарами продавца.
-- -----------------------------------------------------------------------------
CREATE VIEW seller_revenue AS
SELECT
    s.id                             AS seller_id,
    s.store_name,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products    AS p  ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
JOIN orders      AS o  ON o.id = oi.order_id
WHERE o.status <> 'cancelled'
GROUP BY s.id, s.store_name;

-- -----------------------------------------------------------------------------
-- product_rating — рейтинг товаров: число отзывов и средняя оценка.
-- LEFT JOIN оставляет и товары без отзывов (reviews_count = 0,
-- avg_score = NULL).
-- -----------------------------------------------------------------------------
CREATE VIEW product_rating AS
SELECT
    p.id                   AS product_id,
    p.title,
    c.name                 AS category,
    COUNT(r.id)            AS reviews_count,
    ROUND(AVG(r.score), 2) AS avg_score
FROM products AS p
JOIN categories   AS c ON c.id = p.category_id
LEFT JOIN reviews AS r ON r.product_id = p.id
GROUP BY p.id, p.title, c.name;

-- -----------------------------------------------------------------------------
-- Обращение к представлениям (как к обычным таблицам)
-- -----------------------------------------------------------------------------

-- Пять продавцов с наибольшей выручкой.
SELECT seller_id, store_name, revenue
FROM seller_revenue
ORDER BY revenue DESC
LIMIT 5;

-- Лучшие товары по средней оценке среди товаров, у которых не меньше
-- трёх отзывов.
SELECT product_id, title, category, reviews_count, avg_score
FROM product_rating
WHERE reviews_count >= 3
ORDER BY avg_score DESC, reviews_count DESC, product_id ASC
LIMIT 10;
