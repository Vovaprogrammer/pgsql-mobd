-- =============================================================================
-- Лабораторная работа №6. Планы выполнения и индексы
-- Запускать в базе marketplace (после schema.sql, seed.sql и jsonb.sql).
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

-- Пункт 5. GIN-индекс по JSONB: запрос с @> (условие из пункта 2) до и
-- после создания индекса.
EXPLAIN ANALYZE
SELECT id, title
FROM products
WHERE attributes @> '{"author": "М. Булгаков", "cover": "hard"}';

CREATE INDEX IF NOT EXISTS idx_products_attributes ON products
USING GIN (attributes);

EXPLAIN ANALYZE
SELECT id, title
FROM products
WHERE attributes @> '{"author": "М. Булгаков", "cover": "hard"}';

-- Пункт 6. Цена индексов: массовая вставка 300 000 строк (товары каталога,
-- повторённые 100 раз) в две копии структуры products. У первой индексов
-- нет, у второй — те же, что у products, кроме первичного ключа (id в копиях
-- повторяются).
CREATE TABLE products_no_idx (LIKE products);
CREATE TABLE products_idx    (LIKE products);
CREATE INDEX ON products_idx (seller_id);
CREATE INDEX ON products_idx (category_id);
CREATE INDEX ON products_idx (price);
CREATE INDEX ON products_idx USING GIN (attributes);

EXPLAIN ANALYZE
INSERT INTO products_no_idx
SELECT p.* FROM products AS p CROSS JOIN generate_series(1, 100);

EXPLAIN ANALYZE
INSERT INTO products_idx
SELECT p.* FROM products AS p CROSS JOIN generate_series(1, 100);

DROP TABLE products_no_idx, products_idx;
