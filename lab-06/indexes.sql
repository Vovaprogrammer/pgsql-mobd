-- =============================================================================
-- Лабораторная работа №6. Планы выполнения и индексы
-- Запускать в базе marketplace (после schema.sql и seed.sql).
-- =============================================================================

-- Пункт 3. Планы «тяжёлых» запросов до добавления индексов.
-- ANALYZE обновляет статистику, на которую опирается планировщик.
ANALYZE;

-- ЛР 2, пункт 5: десять самых дорогих активных товаров.
EXPLAIN ANALYZE
SELECT id, title, price
FROM products
WHERE is_active = TRUE
ORDER BY price DESC, title ASC
LIMIT 10;

-- ЛР 3, пункт 5.3: покупатели, у которых есть отменённый заказ.
EXPLAIN ANALYZE
SELECT u.id, u.full_name, u.email
FROM users AS u
WHERE EXISTS (SELECT 1
              FROM orders AS o
              WHERE o.user_id = u.id
                AND o.status = 'cancelled')
ORDER BY u.id ASC
LIMIT 10;

-- Пункт 4. B-tree-индексы под эти запросы и повторные планы.
-- Индекс по цене: строки в нём упорядочены по price.
CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);

-- Частичный индекс: только отменённые заказы, ключ — покупатель.
CREATE INDEX IF NOT EXISTS idx_orders_cancelled_user ON orders(user_id)
WHERE status = 'cancelled';

EXPLAIN ANALYZE
SELECT id, title, price
FROM products
WHERE is_active = TRUE
ORDER BY price DESC, title ASC
LIMIT 10;

EXPLAIN ANALYZE
SELECT u.id, u.full_name, u.email
FROM users AS u
WHERE EXISTS (SELECT 1
              FROM orders AS o
              WHERE o.user_id = u.id
                AND o.status = 'cancelled')
ORDER BY u.id ASC
LIMIT 10;
