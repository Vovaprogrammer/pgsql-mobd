# Лабораторная работа №4. Оконные функции и аналитика данных

Запросы выполняются к базе `marketplace`, созданной `schema.sql` (ЛР 1) и наполненной `seed.sql` (ЛР 2). Тексты запросов — в [`queries.sql`](queries.sql).

## 1. Рейтинг товаров по цене внутри категории

Окно `PARTITION BY p.category_id ORDER BY p.price DESC`: нумерация идёт отдельно в каждой категории, начиная с самого дорогого товара. Показана категория «Косметика», где есть товары с равной ценой.

```sql
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
```
```
 category  |  id  |            title            |  price  | rn | rnk | dense_rnk
-----------+------+-----------------------------+---------+----+-----+-----------
 Косметика | 1465 | Крем для лица Aurora J-305  | 1600.00 |  1 |   1 |         1
 Косметика | 1759 | Крем для лица Volna R-383   | 1600.00 |  2 |   1 |         1
 Косметика | 2725 | Крем для лица Zenit V-125   | 1600.00 |  3 |   1 |         1
 Косметика | 2830 | Крем для лица Lumen W-410   | 1590.00 |  4 |   4 |         2
 Косметика |  688 | Крем для лица Orbita M-356  | 1580.00 |  5 |   5 |         3
 Косметика | 1801 | Крем для лица Aurora H-137  | 1580.00 |  6 |   5 |         3
 Косметика | 2767 | Крем для лица Volna L-779   | 1580.00 |  7 |   5 |         3
 Косметика | 2578 | Крем для лица Kristal E-986 | 1570.00 |  8 |   8 |         4
 Косметика |  373 | Крем для лица Zenit J-401   | 1550.00 |  9 |   9 |         5
 Косметика |  583 | Крем для лица Volna L-971   | 1550.00 | 10 |   9 |         5
(10 rows)
```

Различия на равных ценах (три товара по 1600 руб., затем товар за 1590 руб.):

| Функция | Номера | Правило |
|---|---|---|
| `ROW_NUMBER` | 1, 2, 3, 4 | уникальные номера подряд, равенство цен не учитывается |
| `RANK` | 1, 1, 1, 4 | равным ценам — одинаковый ранг, следующие номера пропускаются |
| `DENSE_RANK` | 1, 1, 1, 2 | равным ценам — одинаковый ранг, без пропусков |

У `ROW_NUMBER` в окно добавлен `p.id`: без него порядок товаров с равной ценой не определён, и их номера могут меняться от запуска к запуску.

## 2. Три самых дорогих товара в каждой категории

В CTE `ranked` товары нумеруются `ROW_NUMBER` по убыванию цены внутри категории, во внешнем запросе остаются строки с `rn <= 3`. Отфильтровать по `rn` в одном запросе нельзя: оконные функции вычисляются после `WHERE`. `ROW_NUMBER` выбран потому, что даёт ровно три товара даже при равных ценах.

```sql
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
```
```
         category          |  id  |               title               |   price   | rn
---------------------------+------+-----------------------------------+-----------+----
 Беспроводные наушники     | 2918 | Беспроводные наушники Zenit G-966 |  11990.00 |  1
 Беспроводные наушники     |  608 | Беспроводные наушники Volna K-996 |  11980.00 |  2
 Беспроводные наушники     |  566 | Беспроводные наушники Zenit U-342 |  11970.00 |  3
 Велосипеды                | 2176 | Велосипед Orbita S-512            |  49970.00 |  1
 Велосипеды                | 2428 | Велосипед Nordis K-836            |  49840.00 |  2
 Велосипеды                | 2722 | Велосипед Kristal S-914           |  49500.00 |  3
 Детские книги             | 1749 | Сборник сказок Lumen H-913        |    800.00 |  1
 Детские книги             |  888 | Сборник сказок Aurora E-556       |    790.00 |  2
 Детские книги             | 1854 | Сборник сказок Volna I-298        |    790.00 |  3
(63 rows)
```

Результат — 63 строки: по три товара в каждой из 21 категории с товарами.

## 3. Нарастающий итог выручки по дням

`GROUP BY o.created_at::date` с внутренним `SUM` даёт выручку дня — сумму `quantity * unit_price` по позициям неотменённых заказов. Внешний `SUM(...) OVER` — оконная агрегатная функция над уже сгруппированными строками: рамка `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` складывает выручку всех дней от первого до текущего.

```sql
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
```
```
    day     | day_revenue | running_total
------------+-------------+---------------
 2025-11-06 |  1147937.32 |    1147937.32
 2025-11-07 |  1060093.04 |    2208030.36
 2025-11-08 |  1175878.93 |    3383909.29
 2025-11-09 |  1704459.78 |    5088369.07
 2025-11-10 |   434972.40 |    5523341.47
(366 rows)
```

На последний день `running_total` = 484066428.16 — это совпадает с общей выручкой по всем неотменённым заказам.

## 4. Доля выручки продавца в выручке его категории

`GROUP BY` по категории и продавцу даёт выручку продавца в категории (`seller_revenue`, без отменённых заказов). Оконный `SUM(SUM(...)) OVER (PARTITION BY c.id)` складывает выручку всех продавцов той же категории (`category_revenue`) и ставит её в каждую строку, не схлопывая их. Доля — частное этих двух сумм в процентах.

```sql
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
```
```
         category          |     seller      | seller_revenue | category_revenue | share_pct
---------------------------+-----------------+----------------+------------------+-----------
 Беспроводные наушники     | ЛавкаМастера 39 |      351552.09 |       6882450.24 |      5.11
 Беспроводные наушники     | ЗелёныйДвор 37  |      285595.06 |       6882450.24 |      4.15
 Беспроводные наушники     | ДомАрт 1        |      276406.60 |       6882450.24 |      4.02
 Беспроводные наушники     | ЛавкаМастера 7  |      265016.02 |       6882450.24 |      3.85
 Беспроводные наушники     | ЛавкаМастера 31 |      244587.22 |       6882450.24 |      3.55
(840 rows)
```

Результат — 840 строк: каждый из 40 продавцов торгует в каждой из 21 категории. Внутри категории `category_revenue` одинакова во всех строках, а доли продавцов в сумме дают 100%.
