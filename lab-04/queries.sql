-- =============================================================================
-- Лабораторная работа №4. Оконные функции и аналитика данных
-- Запросы к базе marketplace (после schema.sql и seed.sql).
-- Номера соответствуют пунктам технического задания.
-- =============================================================================

-- Пункт 1. Рейтинг товаров по цене внутри категории: ROW_NUMBER, RANK,
-- DENSE_RANK. Категория «Косметика» — в ней есть товары с равной ценой.
-- p.id у ROW_NUMBER — чтобы номера товаров с равной ценой не менялись
-- от запуска к запуску.
SELECT
    c.name  AS category,
    p.id,
    p.title,
    p.price,
    ROW_NUMBER() OVER (PARTITION BY p.category_id
                       ORDER BY p.price DESC, p.id ASC) AS rn,
    RANK()       OVER w                                 AS rnk,
    DENSE_RANK() OVER w                                 AS dense_rnk
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
WHERE c.name = 'Косметика'
WINDOW w AS (PARTITION BY p.category_id ORDER BY p.price DESC)
ORDER BY rn ASC
LIMIT 10;

-- Пункт 2. Три самых дорогих товара в каждой категории.
-- В CTE товары нумеруются по убыванию цены внутри категории, во внешнем
-- запросе остаются номера 1..3. Отфильтровать по rn в том же запросе
-- нельзя: оконные функции вычисляются после WHERE.
WITH ranked AS (
    SELECT
        c.name AS category,
        p.id,
        p.title,
        p.price,
        ROW_NUMBER() OVER (PARTITION BY p.category_id
                           ORDER BY p.price DESC, p.id ASC) AS rn
    FROM products AS p
    JOIN categories AS c ON c.id = p.category_id
)
SELECT category, id, title, price, rn
FROM ranked
WHERE rn <= 3
ORDER BY category ASC, rn ASC;

-- Пункт 3. Нарастающий итог выручки по дням.
-- Выручка дня — сумма quantity * unit_price по позициям неотменённых
-- заказов (GROUP BY по дате). Внешний SUM(...) OVER складывает выручку
-- дней от первого до текущего.
SELECT
    o.created_at::date               AS day,
    SUM(oi.quantity * oi.unit_price) AS day_revenue,
    SUM(SUM(oi.quantity * oi.unit_price)) OVER (
        ORDER BY o.created_at::date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                AS running_total
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
WHERE o.status <> 'cancelled'
GROUP BY o.created_at::date
ORDER BY day ASC;
