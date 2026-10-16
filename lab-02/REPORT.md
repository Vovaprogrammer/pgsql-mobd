# Лабораторная работа №2. Базовые SQL-запросы и фильтрация данных

## 1. Наполнение базы данных тестовыми данными

**Задача.** Наполнить все 16 таблиц базы `marketplace` согласованными данными
с помощью `generate_series`; в крупные таблицы (товары, заказы) внести не менее
1000 строк.

**Решение.** Скрипт [`seed.sql`](seed.sql) выполняется после `schema.sql` одной
транзакцией и при повторном запуске воссоздаёт данные заново (в начале —
`TRUNCATE … RESTART IDENTITY CASCADE`). Каждая таблица наполняется командой:

```sql
INSERT INTO таблица (...)
SELECT <выражения от g>
FROM generate_series(1, N) AS g;
```

Значения получаются из номера строки `g` и случайных чисел: `random()` для
дат и цен, массивы `ARRAY[...]` для имён, городов и названий, `%` для
равномерного распределения, `CASE` для статусов и пустых значений. Так как
идентификаторы идут подряд с 1, внешние ключи вычисляются формулами
(например, заказ `g` принадлежит покупателю `51 + (g - 1) % 1150`), а данные
остаются согласованными: суммы заказов равны сумме их позиций, статусы
платежей и доставок соответствуют статусу заказа. Намеренно оставлены
пустые значения (`NULL`) в телефонах, описаниях товаров и квартирах — они
нужны для запросов с `IS NULL`.

**Результат.** Количество строк после выполнения скрипта:

```
  table_name  | rows
--------------+-------
 users        |  1200
 sellers      |    40
 categories   |    27
 products     |  3000
 stock        |  3000
 carts        |   400
 cart_items   |  1200
 addresses    |  2300
 orders       |  5000
 order_items  | 12500
 payments     |  4917
 deliveries   |  4500
 reviews      |  3051
 wishlist     |  4000
 promo_codes  |    15
 promo_usages |  1375
```

Фрагмент таблицы `products`:

```
 id | seller_id | category_id |         title          |  price   | is_active
----+-----------+-------------+------------------------+----------+-----------
  1 |         2 |           8 | Ноутбук Aurora B-137   | 99500.00 | t
  2 |         3 |           9 | Наушники Aurora C-174  |  3350.00 | t
  3 |         4 |          10 | Телевизор Nordis D-211 | 54530.00 | f
```

## 2. Запросы на выборку и фильтрацию

Тексты запросов приведены в [`queries.sql`](queries.sql). Ниже для каждого — назначение, текст и фрагмент результата.

### 2.1 DISTINCT и псевдонимы

Какие сочетания «категория — признак активности» есть в каталоге (без повторов).

```sql
SELECT DISTINCT
    category_id AS category,
    is_active AS active
FROM products
ORDER BY category ASC, active ASC;
```
```
 category | active
----------+--------
        7 | false
        7 | true
        8 | false
        8 | true
(42 rows)
```

### 2.2 AND, OR, скобки и IN

Активные товары дешевле 2000 или из категорий 7 (смартфоны) и 8 (ноутбуки).

```sql
SELECT id, title, price, category_id, is_active
FROM products
WHERE is_active = TRUE
  AND (price < 2000 OR category_id IN (7, 8))
ORDER BY id ASC
LIMIT 10;
```
```
 id |           title            |  price   | category_id | is_active
----+----------------------------+----------+-------------+-----------
  1 | Ноутбук Aurora B-137       | 99500.00 |           8 | t
  5 | Учебник Nordis F-285       |   980.00 |          12 | t
  6 | Сборник сказок Volna G-322 |   230.00 |          13 | t
 12 | Лопата Zenit M-544         |  1370.00 |          19 | t
(10 rows)
```

### 2.3 BETWEEN

Товары с ценой от 3000 до 5000.

```sql
SELECT id, title, price
FROM products
WHERE price BETWEEN 3000 AND 5000
ORDER BY price ASC
LIMIT 10;
```
```
  id  |               title                |  price
------+------------------------------------+---------
 1133 | Беспроводные наушники Nordis P-621 | 3000.00
 1943 | Набор посуды Lumen T-891           | 3010.00
 1330 | Мужская рубашка Kristal E-710      | 3010.00
(10 rows)
```

### 2.4 ILIKE

Поиск смартфонов по названию (регистр не важен, `%` — любая последовательность символов).

```sql
SELECT id, title, price
FROM products
WHERE title ILIKE '%смартфон%'
ORDER BY id ASC
LIMIT 10;
```
```
 id |         title         |  price
----+-----------------------+----------
 21 | Смартфон Lumen V-877  | 44630.00
 42 | Смартфон Tandem Q-754 | 33420.00
 63 | Смартфон Orbita L-631 | 18040.00
(10 rows)
```

### 2.5 IS NULL и COALESCE

Товары без описания; `COALESCE` подставляет текст вместо `NULL`.

```sql
SELECT id, title, COALESCE(description, 'нет описания') AS descr
FROM products
WHERE description IS NULL
ORDER BY id ASC
LIMIT 10;
```
```
 id |            title            |    descr
----+-----------------------------+--------------
  2 | Наушники Aurora C-174       | нет описания
  3 | Телевизор Nordis D-211      | нет описания
  7 | Мужская рубашка Volna H-359 | нет описания
(10 rows)
```

### 2.6 Сортировка по двум столбцам

Самые дорогие активные товары; при равной цене — по названию.

```sql
SELECT id, title, price
FROM products
WHERE is_active = TRUE
ORDER BY price DESC, title ASC
LIMIT 10;
```
```
  id  |             title             |   price
------+-------------------------------+-----------
 1090 | Игровой ноутбук Kristal Y-830 | 217830.00
 2119 | Игровой ноутбук Volna N-203   | 214070.00
 1510 | Игровой ноутбук Lumen C-170   | 213520.00
(10 rows)
```

### 2.7 Постраничный вывод

Страница 2 по 20 товаров: `OFFSET = (номер страницы − 1) × 20`.

```sql
SELECT id, title, price
FROM products
ORDER BY id ASC
LIMIT 20 OFFSET 20;
```
```
 id |          title          |  price
----+-------------------------+----------
 21 | Смартфон Lumen V-877    | 44630.00
 22 | Ноутбук Lumen W-914     | 36190.00
 23 | Наушники Lumen X-951    |  2010.00
(20 rows)
```
