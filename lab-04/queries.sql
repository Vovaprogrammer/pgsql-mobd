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
