# Лабораторная работа №6. Современные возможности PostgreSQL и оптимизация запросов

Скрипты выполняются в базе `marketplace`, созданной `schema.sql` (ЛР 1) и наполненной `seed.sql` (ЛР 2). Работа с JSONB — в [`jsonb.sql`](jsonb.sql), планы выполнения и индексы — в [`indexes.sql`](indexes.sql).

## 1. Столбец JSONB с характеристиками товара

Характеристики товаров разных категорий различаются: у книги — автор, число страниц и переплёт, у одежды — цвет и материал. В отдельных столбцах большая часть значений была бы `NULL`, а новая категория требовала бы изменения схемы, поэтому характеристики хранятся в одном столбце `attributes` типа JSONB. Набор ключей выбирается `CASE` по категории товара, объект собирает `jsonb_build_object(ключ, значение, ...)`. Значения вычисляются из `id`, марка электроники — предпоследнее слово названия (`split_part(title, ' ', -2)`).

```sql
ALTER TABLE products ADD COLUMN IF NOT EXISTS attributes JSONB;

UPDATE products
SET attributes = CASE
    WHEN category_id IN (7, 8, 9, 10, 26, 27) THEN      -- электроника
        jsonb_build_object(
            'brand', split_part(title, ' ', -2),
            'color', (ARRAY['black', 'white', 'grey', 'blue'])[1 + id % 4])
    WHEN category_id IN (11, 12, 13) THEN               -- книги
        jsonb_build_object(
            'author', (ARRAY['Л. Толстой', 'А. Пушкин', 'А. Чехов',
                             'М. Булгаков', 'Н. Гоголь'])[1 + id % 5],
            'pages',  100 + id % 11 * 40,
            'cover',  (ARRAY['hard', 'soft'])[1 + id % 2])
    WHEN category_id IN (14, 15, 16) THEN               -- одежда и обувь
        jsonb_build_object(
            'color',    (ARRAY['black', 'white', 'grey', 'blue'])[1 + id % 4],
            'material', (ARRAY['cotton', 'linen', 'wool', 'viscose',
                               'polyester'])[1 + id % 5])
    WHEN category_id IN (17, 18, 19, 20, 21, 22) THEN   -- дом и сад, спорт
        jsonb_build_object(
            'color',           (ARRAY['black', 'white', 'grey', 'blue'])[1 + id % 4],
            'warranty_months', (ARRAY[6, 12, 18, 24, 36])[1 + id % 5])
    WHEN category_id IN (23, 24, 25) THEN               -- красота и здоровье
        jsonb_build_object(
            'volume_ml', (ARRAY[30, 50, 100, 250])[1 + id % 4])
END;
```

Проверка — по одному товару из каждой корневой категории:

```sql
SELECT id, title, attributes
FROM products
WHERE id IN (1, 4, 7, 10, 13, 16)
ORDER BY id;
```
```
 id |            title            |                       attributes
----+-----------------------------+--------------------------------------------------------
  1 | Ноутбук Aurora B-137        | {"brand": "Aurora", "color": "white"}
  4 | Роман Nordis E-248          | {"cover": "hard", "pages": 260, "author": "Н. Гоголь"}
  7 | Мужская рубашка Volna H-359 | {"color": "blue", "material": "wool"}
 10 | Диван Kristal K-470         | {"color": "grey", "warranty_months": 6}
 13 | Велосипед Zenit N-581       | {"color": "white", "warranty_months": 24}
 16 | Крем для лица Orbita Q-692  | {"volume_ml": 30}
(6 rows)
```

Товары разных категорий получили разные наборы ключей в одном столбце, ключ `color` общий для электроники, одежды, дома и спорта. Порядок ключей при выводе не совпадает с порядком в `jsonb_build_object`: JSONB хранит документ не как текст, а в разобранном виде.

## 2. Извлечение полей и фильтрация по вхождению фрагмента

Оператор `->` возвращает значение по ключу как JSONB, `->>` — как текст. Запрос выбирает книги от 460 страниц: значение `pages` извлекается как текст и приводится к `int` для сравнения с числом. У товаров без ключа `pages` `->>` возвращает `NULL`, и они не проходят условие, поэтому отбирать категории книг отдельно не нужно.

```sql
SELECT id, title,
       attributes -> 'author'         AS author_json,
       attributes ->> 'author'        AS author,
       (attributes ->> 'pages')::int  AS pages
FROM products
WHERE (attributes ->> 'pages')::int >= 460
ORDER BY id
LIMIT 5;
```
```
 id  |            title             |  author_json  |   author    | pages
-----+------------------------------+---------------+-------------+-------
 109 | Роман Zenit F-533            | "Н. Гоголь"   | Н. Гоголь   |   500
 130 | Роман Kristal A-410          | "Л. Толстой"  | Л. Толстой  |   460
 131 | Учебник Kristal B-447        | "А. Пушкин"   | А. Пушкин   |   500
 152 | Учебник Volna W-324          | "А. Чехов"    | А. Чехов    |   460
 153 | Сборник сказок Kristal X-361 | "М. Булгаков" | М. Булгаков |   500
(5 rows)
```

`->` вернул JSON-строку в кавычках, `->>` — обычный текст.

Оператор `@>` истинен, если документ содержит все пары «ключ — значение» заданного фрагмента. Запрос выбирает книги Булгакова в твёрдом переплёте:

```sql
SELECT id, title, attributes
FROM products
WHERE attributes @> '{"author": "М. Булгаков", "cover": "hard"}'
ORDER BY id
LIMIT 5;
```
```
 id  |            title            |                        attributes
-----+-----------------------------+----------------------------------------------------------
  48 | Сборник сказок Aurora W-976 | {"cover": "hard", "pages": 260, "author": "М. Булгаков"}
  68 | Учебник Tandem Q-816        | {"cover": "hard", "pages": 180, "author": "М. Булгаков"}
  88 | Роман Orbita K-656          | {"cover": "hard", "pages": 100, "author": "М. Булгаков"}
 258 | Сборник сказок Tandem Y-646 | {"cover": "hard", "pages": 300, "author": "М. Булгаков"}
 278 | Учебник Zenit S-486         | {"cover": "hard", "pages": 220, "author": "М. Булгаков"}
(5 rows)
```

В документах есть и ключ `pages`, которого нет во фрагменте: `@>` проверяет только пары фрагмента, остальные ключи документа не важны.

## 3. Планы «тяжёлых» запросов

Из предыдущих работ выбраны два запроса, которые читают намного больше строк, чем возвращают. Перед снятием планов команда `ANALYZE` обновляет статистику, на которую опирается планировщик.

```sql
ANALYZE;
```

Запрос 1 (ЛР 2, пункт 5) — десять самых дорогих активных товаров:

```sql
EXPLAIN ANALYZE
SELECT id, title, price
FROM products
WHERE is_active = TRUE
ORDER BY price DESC, title ASC
LIMIT 10;
```
```
Limit  (cost=239.49..239.52 rows=10 width=46) (actual time=0.628..0.629 rows=10.00 loops=1)
  Buffers: shared hit=150
  ->  Sort  (cost=239.49..246.37 rows=2753 width=46) (actual time=0.627..0.628 rows=10.00 loops=1)
        Sort Key: price DESC, title
        Sort Method: top-N heapsort  Memory: 26kB
        Buffers: shared hit=150
        ->  Seq Scan on products  (cost=0.00..180.00 rows=2753 width=46) (actual time=0.014..0.303 rows=2753.00 loops=1)
              Filter: is_active
              Rows Removed by Filter: 247
              Buffers: shared hit=150
Planning Time: 0.124 ms
Execution Time: 0.641 ms
```

`Seq Scan` читает все 3000 строк `products` (150 страниц) и отбрасывает 247 неактивных, затем `Sort` упорядочивает оставшиеся 2753 строки, чтобы вернуть 10. Время выполнения — 0.641 мс.

Запрос 2 (ЛР 3, пункт 5.3) — покупатели, у которых есть отменённый заказ:

```sql
EXPLAIN ANALYZE
SELECT u.id, u.full_name, u.email
FROM users AS u
WHERE EXISTS (SELECT 1
              FROM orders AS o
              WHERE o.user_id = u.id
                AND o.status = 'cancelled')
ORDER BY u.id ASC
LIMIT 10;
```
```
Limit  (cost=3.27..28.57 rows=10 width=52) (actual time=0.034..0.186 rows=10.00 loops=1)
  Buffers: shared hit=471
  ->  Merge Semi Join  (cost=3.27..635.69 rows=250 width=52) (actual time=0.034..0.185 rows=10.00 loops=1)
        Merge Cond: (u.id = o.user_id)
        Buffers: shared hit=471
        ->  Index Scan using users_pkey on users u  (cost=0.28..62.28 rows=1200 width=52) (actual time=0.008..0.023 rows=143.00 loops=1)
              Index Searches: 1
              Buffers: shared hit=4
        ->  Index Scan using idx_orders_user on orders o  (cost=0.28..567.29 rows=250 width=8) (actual time=0.014..0.146 rows=24.00 loops=1)
              Filter: (status = 'cancelled'::text)
              Rows Removed by Filter: 440
              Index Searches: 1
              Buffers: shared hit=467
Planning:
  Buffers: shared hit=10
Planning Time: 0.275 ms
Execution Time: 0.207 ms
```

Пользователи и их заказы читаются `Index Scan` в порядке `id` и `user_id` и сопоставляются `Merge Semi Join`. Индекс `idx_orders_user` не содержит статуса заказа, поэтому из 464 прочитанных заказов 440 отбрасываются фильтром `status = 'cancelled'`; на это уходит 467 обращений к страницам. Время выполнения — 0.207 мс.

## 4. B-tree-индексы и сравнение планов

Под каждый запрос добавлен свой индекс. `idx_products_price` хранит товары упорядоченными по цене. `idx_orders_cancelled_user` — частичный индекс: в него попадают только отменённые заказы, ключ — покупатель.

```sql
CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);

CREATE INDEX IF NOT EXISTS idx_orders_cancelled_user ON orders(user_id)
WHERE status = 'cancelled';
```

План запроса 1 после добавления индекса (текст запроса — в пункте 3):

```
Limit  (cost=0.73..3.53 rows=10 width=46) (actual time=0.033..0.035 rows=10.00 loops=1)
  Buffers: shared hit=13
  ->  Incremental Sort  (cost=0.73..772.07 rows=2753 width=46) (actual time=0.032..0.033 rows=10.00 loops=1)
        Sort Key: price DESC, title
        Presorted Key: price
        Full-sort Groups: 1  Sort Method: quicksort  Average Memory: 26kB  Peak Memory: 26kB
        Buffers: shared hit=13
        ->  Index Scan Backward using idx_products_price on products  (cost=0.28..689.28 rows=2753 width=46) (actual time=0.013..0.021 rows=11.00 loops=1)
              Filter: is_active
              Index Searches: 1
              Buffers: shared hit=13
Planning Time: 0.111 ms
Execution Time: 0.052 ms
```

`Index Scan Backward` читает индекс с конца, от самой высокой цены, поэтому строки сразу приходят упорядоченными по `price DESC`. `Incremental Sort` доупорядочивает по `title` только товары с одинаковой ценой (`Presorted Key: price`). Вместо 3000 строк прочитано 11: одиннадцатая нужна, чтобы убедиться, что у следующего товара цена уже другая.

План запроса 2 после добавления индекса:

```
Limit  (cost=3.13..6.54 rows=10 width=52) (actual time=0.021..0.041 rows=10.00 loops=1)
  Buffers: shared hit=6
  ->  Merge Semi Join  (cost=3.13..88.29 rows=250 width=52) (actual time=0.021..0.039 rows=10.00 loops=1)
        Merge Cond: (u.id = o.user_id)
        Buffers: shared hit=6
        ->  Index Scan using users_pkey on users u  (cost=0.28..62.28 rows=1200 width=52) (actual time=0.006..0.020 rows=143.00 loops=1)
              Index Searches: 1
              Buffers: shared hit=4
        ->  Index Only Scan using idx_orders_cancelled_user on orders o  (cost=0.14..19.89 rows=250 width=8) (actual time=0.004..0.006 rows=24.00 loops=1)
              Heap Fetches: 0
              Index Searches: 1
              Buffers: shared hit=2
Planning:
  Buffers: shared hit=10
Planning Time: 0.280 ms
Execution Time: 0.056 ms
```

В частичном индексе только отменённые заказы, поэтому фильтр по статусу больше не нужен. `Index Only Scan` берёт `user_id` прямо из индекса, таблица `orders` не читается (`Heap Fetches: 0`): вместо 464 строк прочитано 24 записи индекса на 2 страницах.

| Запрос | Сканирование до | Время до | Сканирование после | Время после |
|---|---|---|---|---|
| ЛР 2, п. 5 | `Seq Scan` + `Sort`: 3000 строк, 150 страниц | 0.641 мс | `Index Scan Backward` + `Incremental Sort`: 11 строк, 13 страниц | 0.052 мс |
| ЛР 3, п. 5.3 | `Index Scan` с фильтром: 464 строки, 471 страница | 0.207 мс | `Index Only Scan`: 24 строки, 6 страниц | 0.056 мс |

Планировщик выбрал новые планы, потому что их оценочная стоимость ниже: 239.52 → 3.53 и 28.57 → 6.54. Время сократилось примерно в 12 и в 4 раза.

## 5. GIN-индекс по JSONB

B-tree сравнивает значения целиком и для оператора `@>` не подходит. GIN — инвертированный индекс: для каждого ключа и значения внутри документов он хранит список строк, где они встречаются. Запрос выбирает все товары с условием из пункта 2, без `ORDER BY id LIMIT 5`: с ним планировщику выгоднее идти по первичному ключу и остановиться на пятой найденной книге.

План до создания индекса:

```sql
EXPLAIN ANALYZE
SELECT id, title
FROM products
WHERE attributes @> '{"author": "М. Булгаков", "cover": "hard"}';
```
```
Seq Scan on products  (cost=0.00..187.50 rows=44 width=41) (actual time=0.016..0.455 rows=43.00 loops=1)
  Filter: (attributes @> '{"cover": "hard", "author": "М. Булгаков"}'::jsonb)
  Rows Removed by Filter: 2957
  Buffers: shared hit=150
Planning Time: 0.098 ms
Execution Time: 0.467 ms
```

`Seq Scan` проверяет условие у всех 3000 товаров (150 страниц) и отбрасывает 2957.

Создание индекса и план того же запроса после него:

```sql
CREATE INDEX IF NOT EXISTS idx_products_attributes ON products
USING GIN (attributes);
```
```
Bitmap Heap Scan on products  (cost=21.99..118.88 rows=44 width=41) (actual time=0.035..0.071 rows=43.00 loops=1)
  Recheck Cond: (attributes @> '{"cover": "hard", "author": "М. Булгаков"}'::jsonb)
  Heap Blocks: exact=32
  Buffers: shared hit=41
  ->  Bitmap Index Scan on idx_products_attributes  (cost=0.00..21.98 rows=44 width=0) (actual time=0.021..0.021 rows=43.00 loops=1)
        Index Cond: (attributes @> '{"cover": "hard", "author": "М. Булгаков"}'::jsonb)
        Index Searches: 1
        Buffers: shared hit=9
Planning:
  Buffers: shared hit=1
Planning Time: 0.100 ms
Execution Time: 0.087 ms
```

Условие с `@>` стало условием индекса (`Index Cond`). `Bitmap Index Scan` находит по GIN-индексу 43 товара и отмечает страницы таблицы, где они лежат, а `Bitmap Heap Scan` читает только эти 32 страницы. `Recheck Cond` — повторная проверка условия на прочитанных строках: GIN хранит ключи и значения по отдельности и может вернуть лишние строки, здесь их не оказалось. Прочитана 41 страница вместо 150, время сократилось с 0.467 до 0.087 мс.

## 6. Обратная сторона индексов: массовая вставка

Индексы ускоряют чтение, но каждую новую строку нужно добавить в каждый индекс таблицы. Для сравнения созданы две пустые копии структуры `products` (`LIKE` копирует столбцы без индексов и ограничений): у `products_no_idx` индексов нет, у `products_idx` — те же, что у `products`, кроме первичного ключа (`id` в копиях повторяются). В каждую одной командой вставляется 300 000 строк — товары каталога, повторённые 100 раз.

```sql
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
```

Вставка в таблицу без индексов:

```
Insert on products_no_idx  (cost=0.00..3938.50 rows=0 width=0) (actual time=1001.484..1001.485 rows=0.00 loops=1)
  Buffers: shared hit=321298 dirtied=8429 written=8431
  ->  Nested Loop  (cost=0.00..3938.50 rows=300000 width=210) (actual time=0.026..54.490 rows=300000.00 loops=1)
        Buffers: shared hit=150
        ->  Function Scan on generate_series  (cost=0.00..1.00 rows=100 width=0) (actual time=0.012..0.092 rows=100.00 loops=1)
        ->  Materialize  (cost=0.00..195.00 rows=3000 width=210) (actual time=0.000..0.112 rows=3000.00 loops=100)
              Storage: Memory  Maximum Storage: 687kB
              Buffers: shared hit=150
              ->  Seq Scan on products p  (cost=0.00..180.00 rows=3000 width=210) (actual time=0.010..0.233 rows=3000.00 loops=1)
                    Buffers: shared hit=150
Planning:
  Buffers: shared hit=26
Planning Time: 0.146 ms
Execution Time: 1001.579 ms
```

Вставка в таблицу с индексами:

```
Insert on products_idx  (cost=0.00..3938.50 rows=0 width=0) (actual time=3306.247..3306.248 rows=0.00 loops=1)
  Buffers: shared hit=2935471 read=78 dirtied=10837 written=13022
  ->  Nested Loop  (cost=0.00..3938.50 rows=300000 width=210) (actual time=0.024..68.138 rows=300000.00 loops=1)
        Buffers: shared hit=150
        ->  Function Scan on generate_series  (cost=0.00..1.00 rows=100 width=0) (actual time=0.008..0.073 rows=100.00 loops=1)
        ->  Materialize  (cost=0.00..195.00 rows=3000 width=210) (actual time=0.000..0.156 rows=3000.00 loops=100)
              Storage: Memory  Maximum Storage: 687kB
              Buffers: shared hit=150
              ->  Seq Scan on products p  (cost=0.00..180.00 rows=3000 width=210) (actual time=0.010..0.197 rows=3000.00 loops=1)
                    Buffers: shared hit=150
Planning Time: 0.083 ms
Execution Time: 3306.343 ms
```

Планы одинаковы: `Nested Loop` за 54–68 мс составляет 300 000 строк из 100 значений `generate_series` и 3000 товаров (они прочитаны один раз и сохранены в памяти узлом `Materialize`), остальное время уходит на саму вставку (`Insert`). Оценочная стоимость тоже одинакова: планировщик не учитывает обновление индексов, разница видна только по фактическому времени и числу обращений к страницам.

| Таблица | Время вставки | Обращений к страницам |
|---|---|---|
| `products_no_idx` (без индексов) | 1001.6 мс | 321 298 |
| `products_idx` (4 индекса) | 3306.3 мс | 2 935 471 |

С индексами вставка заняла в 3.3 раза больше времени, обращений к страницам — в 9 раз больше: для каждой строки нужно найти место в трёх B-tree-индексах и записать в GIN-индекс каждый ключ и значение из `attributes`.

## 7. Обоснование добавленных индексов

Индексы добавлены только под запросы, в планах которых база читала намного больше строк, чем возвращала (пункты 3 и 5), и только те, которые планировщик действительно выбрал (пункты 4 и 5). Каждый индекс замедляет вставку (пункт 6), поэтому индексов «на всякий случай» нет.

- `idx_products_price` (B-tree по `price`) — для выборки самых дорогих товаров. Без него план читал все 3000 строк (`Seq Scan`) и сортировал 2753, чтобы вернуть 10. Индекс хранит товары упорядоченными по цене, и `Index Scan Backward` читает с его конца 11 строк. Индекс построен по одному столбцу: B-tree читается в обе стороны, а досортировка по `title` (`Incremental Sort`) затрагивает только товары с одинаковой ценой. `is_active` в индекс не включён: неактивных товаров 8%, и фильтр по этому столбцу почти ничего не отбрасывает.
- `idx_orders_cancelled_user` (частичный B-tree по `user_id` для отменённых заказов) — для поиска покупателей с отменённым заказом. Имеющийся `idx_orders_user` не содержит статуса, и план отбрасывал фильтром 440 из 464 прочитанных заказов. В частичном индексе только 250 отменённых заказов из 5002, он занимает 2 страницы и позволяет `Index Only Scan` без обращения к таблице. Составной индекс `(user_id, status)` содержал бы все заказы; частичный меньше и не обновляется при оформлении новых заказов, потому что они создаются со статусом `created`.
- `idx_products_attributes` (GIN по `attributes`) — для фильтрации товаров по характеристикам оператором `@>`. B-tree этот оператор не поддерживает, и без индекса план проверял все 3000 документов (`Seq Scan`). С GIN-индексом условие стало условием индекса (`Index Cond`), и из таблицы читаются только 32 страницы с подходящими товарами.

Для агрегирующих запросов ЛР 3–4 (выручка по продавцам, по дням, по категориям) индексы не добавлены. Эти запросы обрабатывают все строки заказов, и с индексами по столбцам соединений и дат их планы не меняются: `Seq Scan` с `Hash Join` для них оптимален, а лишний индекс только замедлил бы вставку.
