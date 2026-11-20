-- =============================================================================
-- Лабораторная работа №5. Функции на PL/pgSQL
-- Запускать в базе marketplace (после schema.sql и seed.sql).
-- Функции создаются через CREATE OR REPLACE, скрипт можно выполнять повторно.
-- =============================================================================

-- Пункт 2. Атомарное оформление заказа.
-- p_product_ids[i] и p_quantities[i] — товар и количество i-й позиции.
-- Функция создаёт заказ, для каждой позиции проверяет остаток, добавляет
-- позицию по текущей цене и списывает остаток, затем считает сумму заказа.
-- При нехватке товара RAISE EXCEPTION откатывает все изменения вызова.
CREATE OR REPLACE FUNCTION place_order(p_user_id     BIGINT,
                                       p_product_ids BIGINT[],
                                       p_quantities  INT[])
RETURNS BIGINT AS $$
DECLARE
    v_order_id BIGINT;
    v_price    NUMERIC(12,2);
    v_stock    INT;
BEGIN
    INSERT INTO orders (user_id) VALUES (p_user_id) RETURNING id INTO v_order_id;

    FOR i IN 1 .. array_length(p_product_ids, 1) LOOP
        SELECT p.price, s.quantity INTO v_price, v_stock
        FROM products AS p
        JOIN stock    AS s ON s.product_id = p.id
        WHERE p.id = p_product_ids[i];

        IF v_stock < p_quantities[i] THEN
            RAISE EXCEPTION 'Недостаточно товара % на складе: остаток %, заказано %',
                p_product_ids[i], v_stock, p_quantities[i];
        END IF;

        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, p_product_ids[i], p_quantities[i], v_price);

        UPDATE stock SET quantity = quantity - p_quantities[i]
        WHERE product_id = p_product_ids[i];
    END LOOP;

    UPDATE orders
    SET total_amount = (SELECT SUM(quantity * unit_price)
                        FROM order_items
                        WHERE order_id = v_order_id)
    WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- Успешный вызов: 1 шт. товара 2 и 3 шт. товара 5
SELECT place_order(52, ARRAY[2, 5], ARRAY[1, 3]);

-- Ошибочный вызов: товар 2 есть, товара 13 не хватает (остаток 4).
-- В pgAdmin выполнение остановится на ошибке — проверку выполнить отдельно.
SELECT place_order(52, ARRAY[2, 13], ARRAY[1, 10]);

-- Проверка: последний заказ, его позиции и остатки. После ошибочного вызова
-- это по-прежнему заказ из успешного вызова, остаток товара 2 не изменился.
SELECT o.id, o.user_id, o.total_amount, oi.product_id, oi.quantity,
       oi.unit_price, s.quantity AS stock_left
FROM orders      AS o
JOIN order_items AS oi ON oi.order_id = o.id
JOIN stock       AS s  ON s.product_id = oi.product_id
WHERE o.id = (SELECT max(id) FROM orders);
