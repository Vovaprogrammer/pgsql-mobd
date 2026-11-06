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

-- Пункт 4. Доля выручки продавца в выручке его категории.
-- GROUP BY даёт выручку пары «категория — продавец», оконный
-- SUM(...) OVER (PARTITION BY c.id) — выручку всей категории рядом с ней.
SELECT
    c.name                                       AS category,
    s.store_name                                 AS seller,
    SUM(oi.quantity * oi.unit_price)             AS seller_revenue,
    SUM(SUM(oi.quantity * oi.unit_price)) OVER w AS category_revenue,
    ROUND(100 * SUM(oi.quantity * oi.unit_price)
              / SUM(SUM(oi.quantity * oi.unit_price)) OVER w, 2) AS share_pct
FROM order_items AS oi
JOIN orders     AS o ON o.id = oi.order_id
JOIN products   AS p ON p.id = oi.product_id
JOIN categories AS c ON c.id = p.category_id
JOIN sellers    AS s ON s.id = p.seller_id
WHERE o.status <> 'cancelled'
GROUP BY c.id, c.name, s.id, s.store_name
WINDOW w AS (PARTITION BY c.id)
ORDER BY category ASC, share_pct DESC;

-- Пункт 5. Сравнение выручки дня с предыдущим: LAG и LEAD.
-- CTE daily — выручка по дням (как в пункте 3). LAG берёт выручку
-- предыдущего дня, LEAD — следующего; прирост = текущий день − предыдущий.
WITH daily AS (
    SELECT
        o.created_at::date               AS day,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    WHERE o.status <> 'cancelled'
    GROUP BY o.created_at::date
)
SELECT
    day,
    revenue,
    LAG(revenue)  OVER w           AS prev_revenue,
    LEAD(revenue) OVER w           AS next_revenue,
    revenue - LAG(revenue) OVER w  AS growth,
    ROUND(100 * (revenue - LAG(revenue) OVER w)
              / LAG(revenue) OVER w, 2) AS growth_pct
FROM daily
WINDOW w AS (ORDER BY day)
ORDER BY day ASC;

-- Пункт 6. Задача пункта 4 (доля продавца в выручке категории) обычной
-- группировкой, без оконных функций. Оконный вариант — пункт 4.
-- seller_category — выручка пары «категория — продавец» (как GROUP BY в
-- пункте 4); category_total — вторая группировка, по категории; затем
-- итог категории присоединяется к строкам продавцов по category_id.
WITH seller_category AS (
    SELECT
        c.id                             AS category_id,
        c.name                           AS category,
        s.store_name                     AS seller,
        SUM(oi.quantity * oi.unit_price) AS seller_revenue
    FROM order_items AS oi
    JOIN orders     AS o ON o.id = oi.order_id
    JOIN products   AS p ON p.id = oi.product_id
    JOIN categories AS c ON c.id = p.category_id
    JOIN sellers    AS s ON s.id = p.seller_id
    WHERE o.status <> 'cancelled'
    GROUP BY c.id, c.name, s.id, s.store_name
),
category_total AS (
    SELECT category_id, SUM(seller_revenue) AS category_revenue
    FROM seller_category
    GROUP BY category_id
)
SELECT
    sc.category,
    sc.seller,
    sc.seller_revenue,
    ct.category_revenue,
    ROUND(100 * sc.seller_revenue / ct.category_revenue, 2) AS share_pct
FROM seller_category AS sc
JOIN category_total AS ct ON ct.category_id = sc.category_id
ORDER BY sc.category ASC, share_pct DESC;
