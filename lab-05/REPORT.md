# Лабораторная работа №5. Транзакции, целостность данных и серверная логика

Скрипты выполняются в базе `marketplace`, созданной `schema.sql` (ЛР 1) и наполненной `seed.sql` (ЛР 2). Транзакция — в [`transaction.sql`](transaction.sql), функции — в [`functions.sql`](functions.sql), триггеры — в [`triggers.sql`](triggers.sql).

## 1. Транзакция: COMMIT и ROLLBACK

Оформление заказа — три связанных изменения: строка в `orders`, позиция в `order_items` и списание остатка в `stock`. Они выполняются в одной транзакции, чтобы не появился заказ без списания товара или списание без заказа. Состояние базы до и после каждой транзакции проверяется запросом:

```sql
SELECT (SELECT count(*) FROM orders)                       AS orders_cnt,
       (SELECT count(*) FROM order_items)                  AS items_cnt,
       (SELECT quantity FROM stock WHERE product_id = 13) AS stock_13;
```
```
 orders_cnt | items_cnt | stock_13
------------+-----------+----------
       5000 |     12500 |        6
(1 row)
```

Сценарий 1 — покупатель 51 заказывает 2 шт. товара 13, транзакция фиксируется `COMMIT`. `currval(pg_get_serial_sequence('orders', 'id'))` — id заказа, только что созданного первым `INSERT`.

```sql
BEGIN;
INSERT INTO orders (user_id, total_amount) VALUES (51, 2 * 35720.00);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (currval(pg_get_serial_sequence('orders', 'id')), 13, 2, 35720.00);
UPDATE stock SET quantity = quantity - 2 WHERE product_id = 13;
COMMIT;
```
```
 orders_cnt | items_cnt | stock_13
------------+-----------+----------
       5001 |     12501 |        4
(1 row)
```

Все три изменения сохранены: добавились заказ и позиция, остаток уменьшился на 2.

Сценарий 2 — тот же заказ на 10 шт. при остатке 4. Оба `INSERT` выполняются, но `UPDATE` даёт отрицательный остаток и нарушает `CHECK (quantity >= 0)` таблицы `stock`.

```sql
BEGIN;
INSERT INTO orders (user_id, total_amount) VALUES (51, 10 * 35720.00);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (currval(pg_get_serial_sequence('orders', 'id')), 13, 10, 35720.00);
UPDATE stock SET quantity = quantity - 10 WHERE product_id = 13;  -- ошибка
ROLLBACK;
```
```
ERROR:  new row for relation "stock" violates check constraint "stock_quantity_check"
Failing row contains (13, -6, 2026-09-20 22:45:39.39531+03). 

ОШИБКА:  new row for relation "stock" violates check constraint "stock_quantity_check"
SQL state: 23514
Detail: Failing row contains (13, -6, 2026-09-20 22:45:39.39531+03).
```

Проверка после `ROLLBACK`:

```
 orders_cnt | items_cnt | stock_13
------------+-----------+----------
       5001 |     12501 |        4
(1 row)
```

После ошибки PostgreSQL не выполняет остальные команды транзакции, пока она не завершена; `ROLLBACK` отменяет и уже выполненные `INSERT`: число заказов и позиций и остаток те же, что после сценария 1.

## 2. Функция атомарного оформления заказа

`place_order` оформляет заказ из нескольких позиций: `p_product_ids[i]` и `p_quantities[i]` — товар и количество i-й позиции. Функция создаёт заказ, в цикле по позициям проверяет остаток, добавляет позицию по текущей цене товара и списывает остаток, затем записывает сумму заказа и возвращает его id.

```sql
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
```

Вызов функции — одна команда, а каждая команда выполняется в транзакции. Поэтому `RAISE EXCEPTION` прерывает вызов и откатывает все изменения, сделанные функцией до этого момента, без явных `BEGIN` и `ROLLBACK`.

Успешный вызов — 1 шт. товара 2 и 3 шт. товара 5 (остатки до вызова 39 и 54):

```sql
SELECT place_order(52, ARRAY[2, 5], ARRAY[1, 3]);
```
```
 place_order
-------------
        5003
(1 row)
```

Проверка — последний заказ, его позиции и остатки:

```sql
SELECT o.id, o.user_id, o.total_amount, oi.product_id, oi.quantity,
       oi.unit_price, s.quantity AS stock_left
FROM orders      AS o
JOIN order_items AS oi ON oi.order_id = o.id
JOIN stock       AS s  ON s.product_id = oi.product_id
WHERE o.id = (SELECT max(id) FROM orders);
```
```
  id  | user_id | total_amount | product_id | quantity | unit_price | stock_left
------+---------+--------------+------------+----------+------------+------------
 5003 |      52 |      6290.00 |          2 |        1 |    3350.00 |         38
 5003 |      52 |      6290.00 |          5 |        3 |     980.00 |         51
(2 rows)
```

Заказ создан с двумя позициями, сумма 3350 + 3 × 980 = 6290, остатки уменьшились на 1 и 3. Номер 5002 пропущен: его заняла отменённая транзакция из пункта 1, последовательность при откате не возвращает значения.

Ошибочный вызов — товар 2 в наличии, а товара 13 заказано 10 шт. при остатке 4:

```sql
SELECT place_order(52, ARRAY[2, 13], ARRAY[1, 10]);
```
```
ERROR:  Недостаточно товара 13 на складе: остаток 4, заказано 10
CONTEXT:  функция PL/pgSQL place_order(bigint,bigint[],integer[]), строка 16, оператор RAISE 

ОШИБКА:  Недостаточно товара 13 на складе: остаток 4, заказано 10
SQL state: P0001
```

Проверка после ошибки:

```
  id  | user_id | total_amount | product_id | quantity | unit_price | stock_left
------+---------+--------------+------------+----------+------------+------------
 5003 |      52 |      6290.00 |          2 |        1 |    3350.00 |         38
 5003 |      52 |      6290.00 |          5 |        3 |     980.00 |         51
(2 rows)
```

До исключения функция успела создать заказ, добавить позицию с товаром 2 и списать его остаток, но всё это отменено: последним остался заказ 5003, остаток товара 2 по-прежнему 38.

## 3. Функция сводного показателя: выручка продавца за период

`seller_revenue_for_period` возвращает выручку продавца за период с `p_from` по `p_to` включительно — сумму `quantity * unit_price` по позициям неотменённых заказов с его товарами. Запрос внутри функции записывает результат в переменную `v_revenue` (`SELECT ... INTO`), функция возвращает её значение. В отличие от представления `seller_revenue` из ЛР 3, продавец и период передаются параметрами.

```sql
CREATE OR REPLACE FUNCTION seller_revenue_for_period(p_seller_id BIGINT,
                                                     p_from      DATE,
                                                     p_to        DATE)
RETURNS NUMERIC AS $$
DECLARE
    v_revenue NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0) INTO v_revenue
    FROM order_items AS oi
    JOIN orders      AS o ON o.id = oi.order_id
    JOIN products    AS p ON p.id = oi.product_id
    WHERE p.seller_id = p_seller_id
      AND o.status <> 'cancelled'
      AND o.created_at::date BETWEEN p_from AND p_to;

    RETURN v_revenue;
END;
$$ LANGUAGE plpgsql;
```

Выручка продавца 1 («ДомАрт 1») за январь 2026 года:

```sql
SELECT seller_revenue_for_period(1, '2026-01-01', '2026-01-31');
```
```
 seller_revenue_for_period
---------------------------
                1134008.55
(1 row)
```

`COALESCE` возвращает 0 вместо `NULL`, если продаж за период не было.

## 4. Триггер аудита изменения цены

Журнал `product_price_history` хранит товар, старую и новую цену и время изменения. Триггерная функция `log_price_change` добавляет в журнал строку: `OLD` — строка товара до изменения, `NEW` — после.

```sql
CREATE TABLE IF NOT EXISTS product_price_history (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT        NOT NULL
                   REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    old_price  NUMERIC(12,2) NOT NULL,
    new_price  NUMERIC(12,2) NOT NULL,
    changed_at TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION log_price_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO product_price_history (product_id, old_price, new_price)
    VALUES (NEW.id, OLD.price, NEW.price);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_log_price_change
AFTER UPDATE OF price ON products
FOR EACH ROW
WHEN (OLD.price <> NEW.price)
EXECUTE FUNCTION log_price_change();
```

Триггер срабатывает `AFTER` — после того как изменение строки выполнено, `UPDATE OF price` — только на `UPDATE`, затрагивающий столбец `price`, `FOR EACH ROW` — отдельно для каждой изменённой строки. Условие `WHEN` отсекает обновления, при которых цена осталась прежней.

Проверка — одна команда поднимает цену двух товаров на 100 руб.:

```sql
UPDATE products SET price = price + 100 WHERE id IN (2, 5);

SELECT * FROM product_price_history ORDER BY id;
```
```
 id | product_id | old_price | new_price |          changed_at
----+------------+-----------+-----------+-------------------------------
  1 |          2 |   3350.00 |   3450.00 | 2026-11-20 13:07:17.783881+03
  2 |          5 |    980.00 |   1080.00 | 2026-11-20 13:07:17.783881+03
(2 rows)
```

Одна команда `UPDATE` изменила две строки, и триггер уровня строки записал в журнал две строки: старая и новая цена каждого товара попали туда автоматически.
