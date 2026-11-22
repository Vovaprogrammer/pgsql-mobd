# Лабораторная работа №6. Современные возможности PostgreSQL и оптимизация запросов

Скрипты выполняются в базе `marketplace`, созданной `schema.sql` (ЛР 1) и наполненной `seed.sql` (ЛР 2). Работа с JSONB — в [`jsonb.sql`](jsonb.sql).

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
