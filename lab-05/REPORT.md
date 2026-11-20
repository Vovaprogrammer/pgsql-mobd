# Лабораторная работа №5. Транзакции, целостность данных и серверная логика

Скрипты выполняются в базе `marketplace`, созданной `schema.sql` (ЛР 1) и наполненной `seed.sql` (ЛР 2). Транзакция — в [`transaction.sql`](transaction.sql).

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
