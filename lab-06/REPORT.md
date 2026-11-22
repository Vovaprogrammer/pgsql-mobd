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
