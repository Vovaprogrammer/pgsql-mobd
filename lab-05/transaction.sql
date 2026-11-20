-- =============================================================================
-- Лабораторная работа №5. Пункт 1. Транзакция: COMMIT и ROLLBACK
-- Запускать в базе marketplace (после schema.sql и seed.sql).
-- В pgAdmin после ошибки во втором сценарии выполнить ROLLBACK и проверку
-- отдельно: после ошибки выполнение скрипта останавливается.
-- =============================================================================

-- Состояние до транзакций: число заказов, позиций и остаток товара 13
SELECT (SELECT count(*) FROM orders)                       AS orders_cnt,
       (SELECT count(*) FROM order_items)                  AS items_cnt,
       (SELECT quantity FROM stock WHERE product_id = 13) AS stock_13;

-- Сценарий 1. Покупатель 51 заказывает 2 шт. товара 13: заказ, позиция и
-- списание остатка фиксируются вместе. currval(...) — id только что
-- созданного заказа.
BEGIN;
INSERT INTO orders (user_id, total_amount) VALUES (51, 2 * 35720.00);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (currval(pg_get_serial_sequence('orders', 'id')), 13, 2, 35720.00);
UPDATE stock SET quantity = quantity - 2 WHERE product_id = 13;
COMMIT;

SELECT (SELECT count(*) FROM orders)                       AS orders_cnt,
       (SELECT count(*) FROM order_items)                  AS items_cnt,
       (SELECT quantity FROM stock WHERE product_id = 13) AS stock_13;

-- Сценарий 2. Тот же заказ на 10 шт. при остатке 4: UPDATE нарушает
-- CHECK (quantity >= 0) таблицы stock, транзакция откатывается.
BEGIN;
INSERT INTO orders (user_id, total_amount) VALUES (51, 10 * 35720.00);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (currval(pg_get_serial_sequence('orders', 'id')), 13, 10, 35720.00);
UPDATE stock SET quantity = quantity - 10 WHERE product_id = 13;  -- ошибка
ROLLBACK;

-- Проверка: заказ и позиция из сценария 2 не сохранились, остаток прежний
SELECT (SELECT count(*) FROM orders)                       AS orders_cnt,
       (SELECT count(*) FROM order_items)                  AS items_cnt,
       (SELECT quantity FROM stock WHERE product_id = 13) AS stock_13;
